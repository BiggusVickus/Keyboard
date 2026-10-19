import Foundation

/// Offline de/het check for Dutch. Finds:
/// - de/het with the wrong noun: "het auto" → "de auto", "de grote huis" → "het grote huis"
/// - deze/dit (this) with the wrong noun: "deze huis" → "dit huis"
/// - die/dat (that) with the wrong noun: "met die huis" → "met dat huis"
/// - het/dit/dat with a plural: "het boeken" → "de boeken"
/// - een + adjective with -e + het-word: "een grote huis" → "een groot huis"
/// It only flags nouns it knows, so it stays quiet rather than guess.
public struct DutchArticleChecker: Sendable {
    private let dictionary: NounDictionary

    public init(dictionary: NounDictionary = .dutch) {
        self.dictionary = dictionary
    }

    struct Token {
        let text: String
        let lower: String
        /// Character positions in the text (for checking what's between two words).
        let start: Int
        let end: Int
        let range: UTF16Range
    }

    public func check(_ text: String) -> [GrammarIssue] {
        let chars = Array(text)
        let tokens = Self.tokens(in: chars)
        var issues: [GrammarIssue] = []

        var i = 0
        while i < tokens.count {
            if let found = findIssue(at: i, tokens: tokens, chars: chars, text: text) {
                issues.append(found.issue)
                i = found.lastToken + 1
            } else {
                i += 1
            }
        }
        return issues
    }

    // MARK: - Rules

    enum Determiner {
        case article              // de, het
        case demonstrative        // deze, dit (this)
        case distantDemonstrative // die, dat (that)
        case indefinite           // een, geen

        init?(_ word: String) {
            switch word {
            case "de", "het": self = .article
            case "deze", "dit": self = .demonstrative
            case "die", "dat": self = .distantDemonstrative
            case "een", "geen": self = .indefinite
            default: return nil
            }
        }

        /// The right word for a noun of this gender.
        func expected(for gender: DutchGender) -> String? {
            switch self {
            case .article: gender.rawValue
            case .demonstrative: gender.demonstrative
            case .distantDemonstrative: gender.distantDemonstrative
            case .indefinite: nil
            }
        }

        var ruleID: String {
            switch self {
            case .article: "TAALHULP_DE_HET"
            case .demonstrative: "TAALHULP_DEZE_DIT"
            case .distantDemonstrative: "TAALHULP_DIE_DAT"
            case .indefinite: "TAALHULP_EEN_ADJ_HET"
            }
        }
    }

    private func findIssue(at i: Int, tokens: [Token], chars: [Character], text: String) -> (issue: GrammarIssue, lastToken: Int)? {
        let first = tokens[i]
        guard let determiner = Determiner(first.lower) else { return nil }
        // "Ik vind het tijd…", "Ze noemen het liefde": here het is a pronoun, not an article.
        if first.lower == "het", i > 0, Self.pronounVerbs.contains(tokens[i - 1].lower) { return nil }
        // "…dat het nacht was", "als het pakjesavond is": after these, het is usually the subject (it).
        if first.lower == "het", i > 0, Self.subordinators.contains(tokens[i - 1].lower) { return nil }

        // The noun is the next word, or the one after a single adjective ending in -e.
        guard i + 1 < tokens.count, Self.adjacent(first, tokens[i + 1], chars) else { return nil }
        var adjective: Token?
        var adjectiveBase: String?
        var noun = tokens[i + 1]
        var found = DutchNouns.gender(of: noun.text, dictionary: dictionary)
        if found == nil, let base = inflectedAdjectiveBase(noun.lower),
           i + 2 < tokens.count, Self.adjacent(noun, tokens[i + 2], chars) {
            adjective = noun
            adjectiveBase = base
            noun = tokens[i + 2]
            found = DutchNouns.gender(of: noun.text, dictionary: dictionary)
        }
        guard let gender = found?.gender, let reason = found?.reason else { return nil }
        let isPlural = reason == .plural

        // A capital in the middle of a sentence means a name: het Binnenhof, de Hoge Veluwe.
        if noun.text.first?.isUppercase == true || adjective?.text.first?.isUppercase == true { return nil }
        // "de fruit- en groenteboer": only half a word.
        if noun.end < chars.count, chars[noun.end] == "-" { return nil }
        // "de nummer vier" is a team or player, which takes de; "het nummer" is a number or a song.
        if noun.lower == "nummer", Self.isFollowedByNumber(noun, tokens: tokens, chars: chars) { return nil }
        // Plurals in -en look like verbs used as nouns, which take het: met dat armzwaaien, het lopen.
        if isPlural, noun.lower.hasSuffix("en"), !noun.lower.hasSuffix("eren") { return nil }

        if determiner == .demonstrative || determiner == .distantDemonstrative {
            // "Deze werk ik af", "Die ken ik": a pronoun, followed by a verb and its subject.
            let next = adjective == nil ? i + 2 : i + 3
            if next < tokens.count, Self.subjectPronouns.contains(tokens[next].lower) { return nil }
        }
        let afterPreposition = i > 0 && Self.adjacent(tokens[i - 1], first, chars)
            && Self.prepositions.contains(tokens[i - 1].lower)
        let startsSentence = Self.startsSentence(first, chars)
        if determiner == .distantDemonstrative {
            // die and dat also mean "who/which" and "that" (Ik denk dat koffie…, mensen die werk zoeken).
            // die certainly means "that one" after a preposition or at the start of a sentence. dat only at
            // the start: after a preposition it can still be the conjunction (Ik ben er zeker van dat tante…).
            // "Dat kinderen spelen, is goed" starts with the conjunction, so plurals are never flagged.
            let sure = first.lower == "die" ? afterPreposition || startsSentence : startsSentence
            guard sure, !isPlural else { return nil }
        }
        if isPlural {
            // "Ik lees het kinderen voor": het (it) is a pronoun and the plural has no article.
            // Before a plural, het/dit/dat are only certainly articles at the start or after a preposition.
            guard afterPreposition || startsSentence else { return nil }
        }

        let range = UTF16Range(location: first.range.location, length: noun.range.end - first.range.location)
        guard let covered = range.substring(in: text) else { return nil }
        let lastIndex = adjective == nil ? i + 1 : i + 2
        let sentence = Self.sentence(from: first.start, to: noun.end, in: chars)

        switch determiner {
        case .article, .demonstrative, .distantDemonstrative:
            guard let expected = determiner.expected(for: gender), first.lower != expected else { return nil }
            let fixed = TextEditing.matchCase(expected, to: first.text) + covered.dropFirst(first.text.count)
            let issue = GrammarIssue(
                range: range, text: covered,
                message: isPlural ? "‘\(noun.lower)’ is meervoud: altijd de, deze of die."
                                  : "‘\(noun.lower)’ is een \(gender.rawValue)-woord.",
                shortMessage: isPlural ? "meervoud" : "\(gender.rawValue)-woord",
                replacements: [fixed],
                ruleID: determiner.ruleID,
                kind: .error, source: .articles, topic: .articles,
                explanation: Self.explanation(noun: noun.lower, gender: gender, reason: reason, determiner: determiner),
                sentence: sentence)
            return (issue, lastIndex)

        case .indefinite:
            // Only "een/geen + adjective + het-word" has a rule to break.
            guard gender == .het, !isPlural, let adjective, let base = adjectiveBase,
                  base != adjective.lower
            else { return nil }
            let plain = TextEditing.matchCase(base, to: adjective.text)
            let fixed = first.text + Self.gap(first, adjective, chars) + plain + Self.gap(adjective, noun, chars) + noun.text
            let issue = GrammarIssue(
                range: range, text: covered,
                message: "Geen -e bij een het-woord na ‘\(first.lower)’.",
                shortMessage: "buigings-e",
                replacements: [fixed],
                ruleID: determiner.ruleID,
                kind: .error, source: .articles, topic: .adjectiveEndings,
                explanation: "‘\(noun.lower)’ is a het-word. After een or geen, an adjective before a singular het-word gets no -e: \(first.lower) \(plain.lowercased()) \(noun.lower). With het it does: het \(adjective.lower) \(noun.lower).",
                sentence: sentence)
            return (issue, lastIndex)
        }
    }

    static func explanation(noun: String, gender: DutchGender, reason: DutchGenderReason,
                            determiner: Determiner) -> String {
        if reason == .plural {
            return "‘\(noun)’ is a plural. Every plural takes de, and deze (these) or die (those): de huizen, deze huizen, die huizen. Dit and dat are only for singular het-words."
        }
        let rule: String
        switch determiner {
        case .demonstrative, .distantDemonstrative:
            rule = "‘\(noun)’ is a \(gender.rawValue)-word, so it takes \(gender.demonstrative) (this) and \(gender.distantDemonstrative) (that). De-words use deze/die, het-words use dit/dat."
        case .article, .indefinite:
            rule = "‘\(noun)’ is a \(gender.rawValue)-word, so it takes \(gender.rawValue)."
        }
        let why: String
        switch reason {
        case .plural:
            why = ""
        case .listed:
            why = "There's no rule for this one; it just has to be learned."
        case .diminutive:
            why = "Words ending in -je (diminutives) are always het-words: het huisje, het meisje."
        case .suffix(let suffix):
            why = "Words ending in -\(suffix) are \(gender.rawValue)-words."
        case .compound(let lastPart):
            why = "In a compound the last part decides: ‘\(lastPart)’ is a \(gender.rawValue)-word."
        }
        return "\(rule) \(why) In the plural every noun takes de: de huizen."
    }

    // MARK: - Adjectives

    /// After these, die/dat can only mean "that": met die auto, in dat huis. Left out on purpose:
    /// voor, door, om, tot, na, zonder, behalve (voordat, doordat, omdat… are often written apart).
    static let prepositions: Set<String> = [
        "in", "op", "met", "van", "bij", "uit", "aan", "over", "onder", "achter", "naast", "tussen",
        "tegen", "naar", "rond", "rondom", "langs", "binnen", "buiten", "boven", "beneden", "sinds",
        "tijdens", "vanaf", "vanuit", "via", "per", "volgens", "ondanks", "wegens", "voorbij",
    ]

    /// "Die ken ik": a demonstrative used as a pronoun is followed by the verb and then the subject.
    static let subjectPronouns: Set<String> = ["ik", "je", "jij", "u", "hij", "zij", "ze", "we", "wij", "jullie", "men"]

    /// Verbs after which "het" is usually a pronoun: "Ik vind het jammer", "We noemen het liefde".
    static let pronounVerbs: Set<String> = [
        "vind", "vindt", "vinden", "vond", "vonden",
        "noem", "noemt", "noemen", "noemde", "noemden",
        "heet", "heten", "heette", "heetten",
    ]

    /// Words that start a subordinate clause; "het" right after them is usually "it".
    static let subordinators: Set<String> = [
        "dat", "als", "of", "omdat", "doordat", "zodat", "wanneer", "toen", "nu", "terwijl", "hoewel",
        "voordat", "nadat", "totdat", "zodra", "tenzij", "indien", "mits", "sinds", "aangezien", "zoals",
        "waar", "wat", "wie", "hoe", "waarom", "welke",
    ]

    /// Words ending in -e that are not inflected adjectives (or never take the -e away).
    static let notInflectedAdjectives: Set<String> = [
        "deze", "die", "elke", "iedere", "welke", "sommige", "enige", "beide", "zelfde", "eigenste",
        "oranje", "roze", "beige", "mauve", "crème", "creme", "moe",
        "eerste", "tweede", "derde", "vierde", "vijfde", "zesde", "zevende", "achtste", "negende", "tiende",
        "laatste", "volgende", "vorige",
    ]

    /// For an adjective with the -e ending, the form without it (grote → groot); nil if the word isn't one.
    /// Uses Wiktionary's adjective forms, and the spelling rules only for words it doesn't know.
    func inflectedAdjectiveBase(_ word: String) -> String? {
        guard !Self.notInflectedAdjectives.contains(word) else { return nil }
        if let base = dictionary.inflectedAdjectiveBase(word) { return base }
        // A word the dictionary knows as something else (a noun, an adverb…) is not an adjective.
        guard dictionary.lookup(word) == nil, Self.looksLikeInflectedAdjective(word) else { return nil }
        // Unknown words in -de/-te are usually past tenses: het speelde gitaar, het haalde adem.
        guard !word.hasSuffix("de"), !word.hasSuffix("te") else { return nil }
        return Self.undeclined(word)?.lowercased()
    }

    static func looksLikeInflectedAdjective(_ word: String) -> Bool {
        word.count >= 3 && word.hasSuffix("e") && !notInflectedAdjectives.contains(word)
    }

    /// Stems that the spelling rules below would get wrong (unstressed last syllable, etc.).
    static let adjectiveExceptions: [String: String] = [
        "algemene": "algemeen", "gemene": "gemeen", "serene": "sereen",
        "originele": "origineel", "criminele": "crimineel",
        "officiële": "officieel", "financiële": "financieel", "materiële": "materieel",
        "essentiële": "essentieel", "potentiële": "potentieel", "reële": "reëel",
    ]

    /// The adjective without its -e: grote → groot, dikke → dik, lieve → lief, boze → boos.
    /// Returns nil when unsure.
    static func undeclined(_ adjective: String) -> String? {
        let lower = adjective.lowercased()
        guard lower.count >= 3, lower.hasSuffix("e") else { return nil }
        if let special = adjectiveExceptions[lower] { return TextEditing.matchCase(special, to: adjective) }
        // Nationalities in -ese: Europese → Europees, Chinese → Chinees.
        if lower.count > 5, lower.hasSuffix("ese") {
            return TextEditing.matchCase(String(lower.dropLast(3)) + "ees", to: adjective)
        }

        var stem = Array(lower.dropLast())
        guard let last = stem.last, !isVowel(last) || last == "i" else { return nil }

        if stem.count >= 2, stem[stem.count - 1] == stem[stem.count - 2], !isVowel(last) {
            // Double consonant: dikke → dik, witte → wit.
            stem.removeLast()
        } else if stem.count >= 2, !isVowel(last), shouldDoubleVowel(stem) {
            // Open syllable: grote → groot, gele → geel, gewone → gewoon.
            stem.insert(stem[stem.count - 2], at: stem.count - 1)
        }
        // A word can't end in v or z: lieve → lief, boze → boos.
        if stem.last == "v" { stem[stem.count - 1] = "f" }
        if stem.last == "z" { stem[stem.count - 1] = "s" }
        return TextEditing.matchCase(String(stem), to: adjective)
    }

    static func isVowel(_ c: Character) -> Bool { "aeiouyäëïöü".contains(c) }

    /// True for a single a/o/u (or e in a one-syllable word) between consonants at the end: "grot", "gel".
    static func shouldDoubleVowel(_ stem: [Character]) -> Bool {
        let n = stem.count
        let vowel = stem[n - 2]
        guard "aeou".contains(vowel) else { return false }
        if n >= 3, isVowel(stem[n - 3]) { return false }   // already a long vowel: groot, mooi, oud
        if vowel == "e" { return vowelGroups(stem) == 1 }   // -el, -er, -en are usually unstressed
        return true
    }

    static func vowelGroups(_ word: [Character]) -> Int {
        var count = 0
        var previousWasVowel = false
        for c in word {
            let vowel = isVowel(c)
            if vowel, !previousWasVowel { count += 1 }
            previousWasVowel = vowel
        }
        return count
    }

    // MARK: - Tokens

    /// Words in the text. Apostrophes and hyphens between letters stay inside the word (auto's).
    static func tokens(in chars: [Character]) -> [Token] {
        var tokens: [Token] = []
        var utf16Offset = 0
        var start: Int?
        var startOffset = 0

        func finish(at end: Int) {
            guard let s = start else { return }
            let text = String(chars[s..<end])
            tokens.append(Token(text: text, lower: text.lowercased(), start: s, end: end,
                                range: UTF16Range(location: startOffset, length: text.utf16.count)))
            start = nil
        }

        for (index, c) in chars.enumerated() {
            let isJoiner = TextEditing.isJoiner(c) && start != nil
                && index + 1 < chars.count && chars[index + 1].isLetter
            if c.isLetter || isJoiner {
                if start == nil {
                    start = index
                    startOffset = utf16Offset
                }
            } else {
                finish(at: index)
            }
            utf16Offset += c.utf16.count
        }
        finish(at: chars.count)
        return tokens
    }

    /// Two words with only spaces between them (no comma, full stop or newline).
    static func adjacent(_ a: Token, _ b: Token, _ chars: [Character]) -> Bool {
        b.start > a.end && chars[a.end..<b.start].allSatisfy { $0 == " " }
    }

    static func gap(_ a: Token, _ b: Token, _ chars: [Character]) -> String {
        String(chars[a.end..<b.start])
    }

    static let numberWords: Set<String> = [
        "een", "één", "twee", "drie", "vier", "vijf", "zes", "zeven", "acht", "negen", "tien", "elf", "twaalf",
    ]

    /// "nummer 3", "nummer twee".
    static func isFollowedByNumber(_ token: Token, tokens: [Token], chars: [Character]) -> Bool {
        var i = token.end
        while i < chars.count, chars[i] == " " { i += 1 }
        if i < chars.count, chars[i].isNumber { return true }
        guard let next = tokens.first(where: { $0.start >= token.end }), next.start == i else { return false }
        return numberWords.contains(next.lower)
    }

    static func isBoundary(_ c: Character) -> Bool { c == "." || c == "!" || c == "?" || c.isNewline }

    /// True when only spaces, quotes or a bracket come between the sentence start and this word.
    static func startsSentence(_ token: Token, _ chars: [Character]) -> Bool {
        var i = token.start
        while i > 0, " \"“‘'(".contains(chars[i - 1]) { i -= 1 }
        return i == 0 || isBoundary(chars[i - 1])
    }

    /// The whole sentence around character positions `start..<end`.
    static func sentence(from start: Int, to end: Int, in chars: [Character]) -> String {
        var lower = start
        while lower > 0, !isBoundary(chars[lower - 1]) { lower -= 1 }
        var upper = end
        while upper < chars.count, !isBoundary(chars[upper]) { upper += 1 }
        if upper < chars.count, !chars[upper].isNewline { upper += 1 }   // keep the full stop
        return String(chars[lower..<upper]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
