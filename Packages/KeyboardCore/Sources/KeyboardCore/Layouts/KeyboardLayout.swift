import Foundation

/// One key on the keyboard.
public struct Key: Hashable, Identifiable, Sendable {
    public enum Kind: Hashable, Sendable {
        /// Types a character. The layout stores it in lowercase; shift makes it uppercase.
        case character(String)
        case shift
        case delete
        case space
        case returnKey
        /// The system "next keyboard" globe key (only shown when iOS asks for it).
        case globe
        /// Switches between EN / DE / NL.
        case languageSwitch
        /// Switches between the letter, number and symbol pages.
        case page(KeyboardPage)
    }

    public let kind: Kind
    /// Relative width: 1 = a normal letter key.
    public let width: Double
    /// Characters offered when the key is long-pressed (e.g. e → é è ë ê).
    public let alternates: [String]
    /// Position in the layout, so two identical keys still have different IDs.
    public let id: String

    public init(_ kind: Kind, width: Double = 1, alternates: [String] = [], id: String) {
        self.kind = kind
        self.width = width
        self.alternates = alternates
        self.id = id
    }

    /// The character this key types, or nil for special keys (shift, delete, …).
    public var character: String? {
        if case .character(let c) = kind { return c }
        return nil
    }
}

/// The three key pages of the keyboard.
public enum KeyboardPage: Hashable, Sendable {
    case letters
    case numbers
    case symbols
}

/// A full keyboard page: rows of keys.
public struct KeyboardLayout: Sendable {
    public let rows: [[Key]]

    public init(rows: [[Key]]) {
        self.rows = rows
    }

    /// Builds the layout for one language and page.
    /// - Parameter showsGlobe: iOS tells the keyboard whether it must show its own globe key
    ///   (`needsInputModeSwitchKey`). On iPhones with a globe key below the keyboard it is hidden.
    /// - Parameter field: e-mail and web address fields get "@", "." and "/" next to the space bar.
    public static func make(language: KeyboardLanguage, page: KeyboardPage, showsGlobe: Bool,
                            field: FieldKind = .text) -> KeyboardLayout {
        let charRows: [[String]]
        switch page {
        case .letters: charRows = letterRows(for: language)
        case .numbers: charRows = numberRows
        case .symbols: charRows = symbolRows
        }

        var rows: [[Key]] = []
        for (rowIndex, chars) in charRows.enumerated() {
            var row = chars.enumerated().map { index, char in
                Key(.character(char),
                    alternates: alternates(for: char, language: language, page: page),
                    id: "\(rowIndex)-\(index)-\(char)")
            }
            // Last character row gets shift (or the page toggle) on the left and delete on the right.
            if rowIndex == charRows.count - 1 {
                switch page {
                case .letters: row.insert(Key(.shift, width: 1.4, id: "shift"), at: 0)
                case .numbers: row.insert(Key(.page(.symbols), width: 1.4, id: "to-symbols"), at: 0)
                case .symbols: row.insert(Key(.page(.numbers), width: 1.4, id: "to-numbers"), at: 0)
                }
                row.append(Key(.delete, width: 1.4, id: "delete"))
            }
            rows.append(row)
        }

        var bottom: [Key] = [
            Key(.page(page == .letters ? .numbers : .letters), width: 1.4, id: "page-toggle"),
        ]
        if showsGlobe {
            bottom.append(Key(.globe, width: 1.1, id: "globe"))
        }
        bottom.append(Key(.languageSwitch, width: 1.1, id: "language"))
        bottom.append(Key(.space, width: 5, id: "space"))
        if page == .letters {
            for char in extraBottomKeys(for: field) {
                bottom.append(Key(.character(char), alternates: alternates(for: char, language: language, page: .letters),
                                  id: "extra-\(char)"))
            }
        }
        bottom.append(Key(.returnKey, width: 2, id: "return"))
        rows.append(bottom)

        return KeyboardLayout(rows: rows)
    }

    /// A period sits right of the space bar on every letter page; long-press it for ".com", ".nl"…
    static func extraBottomKeys(for field: FieldKind) -> [String] {
        switch field {
        case .text: ["."]
        case .email: ["@", "."]
        case .url: [".", "/"]
        case .webSearch: ["."]
        }
    }

    // MARK: - Letter rows per language

    /// All three languages use plain QWERTY. German umlauts and ß are on long-press (a, o, u, s).
    static func letterRows(for language: KeyboardLanguage) -> [[String]] {
        [
            ["q", "w", "e", "r", "t", "y", "u", "i", "o", "p"],
            ["a", "s", "d", "f", "g", "h", "j", "k", "l"],
            ["z", "x", "c", "v", "b", "n", "m"],
        ]
    }

    static let numberRows: [[String]] = [
        ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"],
        ["-", "/", ":", ";", "(", ")", "€", "&", "@", "\""],
        [".", ",", "?", "!", "'"],
    ]

    static let symbolRows: [[String]] = [
        ["[", "]", "{", "}", "#", "%", "^", "*", "+", "="],
        ["_", "\\", "|", "~", "<", ">", "$", "£", "¥", "•"],
        [".", ",", "?", "!", "'"],
    ]

    // MARK: - Long-press alternates

    /// What long-pressing a key offers, like the iOS keyboard: accents on letters, ¡ ¿ ° and other
    /// currencies on the number and symbol pages, and web endings on the period next to the space bar.
    static func alternates(for char: String, language: KeyboardLanguage, page: KeyboardPage) -> [String] {
        switch page {
        case .letters:
            if char == "." { return urlEndings(for: language) }
            return letterAlternates(for: char, language: language)
        case .numbers, .symbols:
            return symbolAlternates[char] ?? []
        }
    }

    /// Accents in iOS order, with the ones a language uses most moved to the front.
    static func letterAlternates(for char: String, language: KeyboardLanguage) -> [String] {
        let preferred: [String]
        switch (language, char) {
        case (.german, "a"): preferred = ["ä"]
        case (.german, "o"): preferred = ["ö"]
        case (.german, "u"): preferred = ["ü"]
        case (.german, "s"): preferred = ["ß"]
        // Dutch: diaeresis (ë, ï) and acute accents for stress (één, dát) are the common ones.
        case (.dutch, "e"): preferred = ["é", "ë"]
        case (.dutch, "i"): preferred = ["ï", "í", "ij"]
        case (.dutch, "o"): preferred = ["ó", "ö"]
        case (.dutch, "a"): preferred = ["á", "ä"]
        case (.dutch, "u"): preferred = ["ú", "ü"]
        case (.dutch, "y"): preferred = ["ij"]
        default: preferred = []
        }
        var result = preferred
        for accent in letterAccents[char] ?? [] where !result.contains(accent) {
            result.append(accent)
        }
        return result
    }

    static let letterAccents: [String: [String]] = [
        "a": ["à", "á", "â", "ä", "æ", "ã", "å", "ā"],
        "c": ["ç", "ć", "č"],
        "e": ["è", "é", "ê", "ë", "ē", "ė", "ę"],
        "i": ["î", "ï", "í", "ī", "į", "ì"],
        "l": ["ł"],
        "n": ["ñ", "ń"],
        "o": ["ô", "ö", "ò", "ó", "œ", "ø", "ō", "õ"],
        "s": ["ß", "ś", "š"],
        "u": ["û", "ü", "ù", "ú", "ū"],
        "y": ["ÿ"],
        "z": ["ž", "ź", "ż"],
    ]

    static let symbolAlternates: [String: [String]] = [
        "0": ["°"],
        "-": ["–", "—", "•"],
        "/": ["\\"],
        "€": ["$", "£", "¥", "₩", "₽", "¢", "₹"],
        "$": ["€", "£", "¥", "₩", "₽", "¢", "₹"],
        "&": ["§"],
        "\"": ["„", "“", "”", "«", "»"],
        "'": ["‘", "’", "‚", "`"],
        ".": ["…"],
        "?": ["¿"],
        "!": ["¡"],
        "%": ["‰"],
        "=": ["≠", "≈"],
    ]

    /// The most common web address endings, starting with the language's own country.
    public static func urlEndings(for language: KeyboardLanguage) -> [String] {
        switch language {
        case .dutch: [".nl", ".com", ".be", ".eu", ".org", ".net"]
        case .german: [".de", ".com", ".at", ".ch", ".eu", ".org"]
        case .english: [".com", ".org", ".net", ".co.uk", ".io", ".edu"]
        }
    }
}
