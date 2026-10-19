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
                    alternates: page == .letters ? alternates(for: char, language: language) : [],
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
                bottom.append(Key(.character(char), id: "extra-\(char)"))
            }
        }
        bottom.append(Key(.returnKey, width: 2, id: "return"))
        rows.append(bottom)

        return KeyboardLayout(rows: rows)
    }

    static func extraBottomKeys(for field: FieldKind) -> [String] {
        switch field {
        case .text: []
        case .email: ["@", "."]
        case .url: [".", "/"]
        case .webSearch: ["."]
        }
    }

    // MARK: - Letter rows per language

    static func letterRows(for language: KeyboardLanguage) -> [[String]] {
        switch language {
        case .english, .dutch:
            // Dutch keyboards in the Netherlands use plain QWERTY; accents are on long-press.
            return [
                ["q", "w", "e", "r", "t", "y", "u", "i", "o", "p"],
                ["a", "s", "d", "f", "g", "h", "j", "k", "l"],
                ["z", "x", "c", "v", "b", "n", "m"],
            ]
        case .german:
            // German QWERTZ with umlauts on their own keys, like the iOS German keyboard.
            return [
                ["q", "w", "e", "r", "t", "z", "u", "i", "o", "p", "ü"],
                ["a", "s", "d", "f", "g", "h", "j", "k", "l", "ö", "ä"],
                ["y", "x", "c", "v", "b", "n", "m"],
            ]
        }
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

    static func alternates(for char: String, language: KeyboardLanguage) -> [String] {
        switch (language, char) {
        case (.german, "s"): return ["ß", "ś", "š"]
        case (.german, "a"): return ["ä", "à", "á", "â"]
        case (.german, "o"): return ["ö", "ò", "ó", "ô"]
        case (.german, "u"): return ["ü", "ù", "ú", "û"]
        case (.german, "e"): return ["é", "è", "ê", "ë"]
        // Dutch: diaeresis (ë, ï) and acute accents for stress (één, dát) are the common ones.
        case (.dutch, "e"): return ["é", "ë", "è", "ê"]
        case (.dutch, "i"): return ["ï", "í", "ì", "î", "ij"]
        case (.dutch, "o"): return ["ó", "ö", "ò", "ô"]
        case (.dutch, "a"): return ["á", "ä", "à", "â"]
        case (.dutch, "u"): return ["ú", "ü", "ù", "û"]
        case (.dutch, "y"): return ["ij"]
        case (.english, "e"): return ["é", "è", "ê", "ë"]
        case (.english, "a"): return ["à", "á", "â", "ä"]
        case (.english, "o"): return ["ó", "ò", "ô", "ö"]
        case (.english, "u"): return ["ú", "ù", "û", "ü"]
        case (.english, "i"): return ["í", "ì", "î", "ï"]
        case (_, "c"): return ["ç"]
        case (_, "n"): return ["ñ"]
        default: return []
        }
    }
}
