import Foundation

/// Offline de/het check for Dutch. Finds:
/// - de/het with the wrong noun: "het auto" → "de auto", "de grote huis" → "het grote huis"
/// - deze/dit with the wrong noun: "deze huis" → "dit huis"
/// - een + adjective with -e + het-word: "een grote huis" → "een groot huis"
/// It only flags nouns it knows, so it stays quiet rather than guess.
public struct DutchArticleChecker: Sendable {
    public init() {}

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

    private enum Determiner {
        case article      // de, het
        case demonstrative // deze, dit
        case indefinite    // een, geen

        init?(_ word: String) {
            switch word {
            case "de", "het": self = .article
            case "deze", "dit": self = .demonstrative
            case "een", "geen": self = .indefinite
            default: return nil
            }
        }
    }

    private func findIssue(at i: Int, tokens: [Token], chars: [Character], text: String) -> (issue: GrammarIssue, lastToken: Int)? {
        let first = tokens[i]
        guard let determiner = Determiner(first.lower) else { return nil }
        // "Ik vind het tijd…", "Ze noemen het liefde": here het is a pronoun, not an article.
        if first.lower == "het", i > 0, Self.pronounVerbs.contains(tokens[i - 1].lower) { return nil }

        // The noun is the next word, or the one after a single adjective ending in -e.
        guard i + 1 < tokens.count, Self.adjacent(first, tokens[i + 1], chars) else { return nil }
        var adjective: Token?
        var noun = tokens[i + 1]
        var found = DutchNouns.gender(of: noun.text)
        if found == nil, Self.looksLikeInflectedAdjective(noun.lower),
           i + 2 < tokens.count, Self.adjacent(noun, tokens[i + 2], chars) {
            adjective = noun
            noun = tokens[i + 2]
            found = DutchNouns.gender(of: noun.text)
        }
        guard let gender = found?.gender, let reason = found?.reason else { return nil }

        let range = UTF16Range(location: first.range.location, length: noun.range.end - first.range.location)
        guard let covered = range.substring(in: text) else { return nil }
        let lastIndex = adjective == nil ? i + 1 : i + 2
        let sentence = Self.sentence(from: first.start, to: noun.end, in: chars)

        switch determiner {
        case .article, .demonstrative:
            let isDemonstrative = determiner == .demonstrative
            let expected = isDemonstrative ? gender.demonstrative : gender.rawValue
            guard first.lower != expected else { return nil }
            let fixed = TextEditing.matchCase(expected, to: first.text) + covered.dropFirst(first.text.count)
            let issue = GrammarIssue(
                range: range, text: covered,
                message: "‘\(noun.lower)’ is een \(gender.rawValue)-woord.",
                shortMessage: "\(gender.rawValue)-woord",
                replacements: [fixed],
                ruleID: isDemonstrative ? "TAALHULP_DEZE_DIT" : "TAALHULP_DE_HET",
                kind: .error, source: .articles, topic: .articles,
                explanation: Self.explanation(noun: noun.lower, gender: gender, reason: reason,
                                              demonstrative: isDemonstrative),
                sentence: sentence)
            return (issue, lastIndex)

        case .indefinite:
            // Only "een/geen + adjective + het-word" has a rule to break.
            guard gender == .het, let adjective,
                  let plain = Self.undeclined(adjective.text), plain != adjective.text
            else { return nil }
            let fixed = first.text + Self.gap(first, adjective, chars) + plain + Self.gap(adjective, noun, chars) + noun.text
            let issue = GrammarIssue(
                range: range, text: covered,
                message: "Geen -e bij een het-woord na ‘\(first.lower)’.",
                shortMessage: "buigings-e",
                replacements: [fixed],
                ruleID: "TAALHULP_EEN_ADJ_HET",
                kind: .error, source: .articles, topic: .adjectiveEndings,
                explanation: "‘\(noun.lower)’ is a het-word. After een or geen, an adjective before a singular het-word gets no -e: \(first.lower) \(plain.lowercased()) \(noun.lower). With het it does: het \(adjective.lower) \(noun.lower).",
                sentence: sentence)
            return (issue, lastIndex)
        }
    }

    static func explanation(noun: String, gender: DutchGender, reason: DutchGenderReason, demonstrative: Bool) -> String {
        let rule = demonstrative
            ? "‘\(noun)’ is a \(gender.rawValue)-word, so it takes \(gender.demonstrative) (this). De-words use deze, het-words use dit."
            : "‘\(noun)’ is a \(gender.rawValue)-word, so it takes \(gender.rawValue)."
        let why: String
        switch reason {
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

    /// Verbs after which "het" is usually a pronoun: "Ik vind het jammer", "We noemen het liefde".
    static let pronounVerbs: Set<String> = [
        "vind", "vindt", "vinden", "vond", "vonden",
        "noem", "noemt", "noemen", "noemde", "noemden",
    ]

    /// Words ending in -e that are not inflected adjectives (or never take the -e away).
    static let notInflectedAdjectives: Set<String> = [
        "deze", "die", "elke", "iedere", "welke", "sommige", "enige", "beide", "zelfde", "eigenste",
        "oranje", "roze", "beige", "mauve", "crème", "creme", "moe",
        "eerste", "tweede", "derde", "vierde", "vijfde", "zesde", "zevende", "achtste", "negende", "tiende",
        "laatste", "volgende", "vorige",
    ]

    static func looksLikeInflectedAdjective(_ word: String) -> Bool {
        word.count >= 3 && word.hasSuffix("e") && !notInflectedAdjectives.contains(word)
            && DutchNouns.gender(of: word) == nil
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

    /// The whole sentence around character positions `start..<end`.
    static func sentence(from start: Int, to end: Int, in chars: [Character]) -> String {
        func isBoundary(_ c: Character) -> Bool { c == "." || c == "!" || c == "?" || c.isNewline }
        var lower = start
        while lower > 0, !isBoundary(chars[lower - 1]) { lower -= 1 }
        var upper = end
        while upper < chars.count, !isBoundary(chars[upper]) { upper += 1 }
        if upper < chars.count, !chars[upper].isNewline { upper += 1 }   // keep the full stop
        return String(chars[lower..<upper]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
