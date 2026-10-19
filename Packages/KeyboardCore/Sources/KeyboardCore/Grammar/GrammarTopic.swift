import Foundation

/// What a grammar issue is about. Used for the English explanation and to group the learning log.
public enum GrammarTopic: String, Codable, CaseIterable, Identifiable, Sendable {
    case articles
    case adjectiveEndings
    case wordOrder
    case verbForms
    case agreement
    case cases
    case spelling
    case capitalization
    case punctuation
    case compounds
    case confusedWords
    case style
    case grammar

    public var id: String { rawValue }

    public func title(for language: KeyboardLanguage) -> String {
        switch self {
        case .articles:
            switch language {
            case .dutch: "de / het"
            case .german: "der / die / das"
            case .english: "a / an / the"
            }
        case .adjectiveEndings: "Adjective endings"
        case .wordOrder: "Word order"
        case .verbForms: "Verb forms"
        case .agreement: "Agreement"
        case .cases: "Cases (den, dem, des…)"
        case .spelling: "Spelling and typos"
        case .capitalization: "Capital letters"
        case .punctuation: "Punctuation and spaces"
        case .compounds: "Compound words"
        case .confusedWords: "Easily confused words"
        case .style: "Style"
        case .grammar: "Grammar"
        }
    }

    /// The general rule, in English, for a learner.
    public func explanation(for language: KeyboardLanguage) -> String {
        switch (self, language) {
        case (.articles, .dutch):
            "Every Dutch noun is a de-word or a het-word, and mostly you have to learn it per word. Some rules help: every plural takes de (de huizen), diminutives ending in -je are always het (het huisje), and words ending in -heid, -ing, -tie or -teit are de. De-words use deze (this) and die (that); het-words use dit and dat; plurals always take de, deze and die."
        case (.articles, .german):
            "Every German noun is masculine (der), feminine (die) or neuter (das), and the article changes with the case: der becomes den (accusative), dem (dative) or des (genitive). Endings help: -ung, -heit, -keit and -schaft are die; -chen and -lein are das."
        case (.articles, .english):
            "Use \"an\" before a vowel sound (an hour, an apple) and \"a\" before a consonant sound (a university, a car)."

        case (.adjectiveEndings, .dutch):
            "An adjective before a noun gets an -e (de grote auto, het grote huis), except before a singular het-word after een, geen or no article: een groot huis, geen groot huis, groot nieuws."
        case (.adjectiveEndings, .german):
            "German adjective endings depend on the article, gender, number and case: der gute Mann, ein guter Mann, mit dem guten Mann, mit einem guten Mann."
        case (.adjectiveEndings, .english):
            "English adjectives never change their ending."

        case (.wordOrder, .dutch):
            "In a main clause the conjugated verb is always in second place: Morgen ga ik naar huis (not: Morgen ik ga). After dat, omdat, als, wanneer, die and other subordinating words, all verbs go to the end: …omdat ik morgen naar huis ga."
        case (.wordOrder, .german):
            "In a main clause the conjugated verb is always in second place: Morgen gehe ich nach Hause. After dass, weil, wenn, ob and other subordinating words, the conjugated verb goes to the very end: …weil ich morgen nach Hause gehe."
        case (.wordOrder, .english):
            "English word order is usually subject, verb, object, and words like often and always go before the main verb: I often go."

        case (.verbForms, .dutch):
            "The verb must match the subject: ik werk, jij/u/hij/zij werkt, wij/jullie/zij werken. When jij or je comes after the verb, drop the -t: Werk jij morgen?"
        case (.verbForms, .german):
            "The verb must match the subject: ich arbeite, du arbeitest, er/sie/es arbeitet, wir/sie/Sie arbeiten, ihr arbeitet. Many common verbs are irregular: ich bin, du bist, er ist."
        case (.verbForms, .english):
            "The verb must match the subject and the tense: he goes, they go; yesterday I went."

        case (.agreement, .dutch):
            "Words that belong together must match: a plural subject takes a plural verb (de kinderen spelen), and a pronoun must match its noun (het huis dat…, de auto die…)."
        case (.agreement, .german):
            "Article, adjective and noun must agree in gender, number and case: der gute Mann, die gute Frau, das gute Kind, den guten Mann (accusative)."
        case (.agreement, .english):
            "Subject and verb must agree in number: the dog barks, the dogs bark."

        case (.cases, .german):
            "The case depends on the word's role and on prepositions. Always dative: aus, bei, mit, nach, seit, von, zu. Always accusative: durch, für, gegen, ohne, um. With in, an, auf, über, unter, vor, hinter, neben and zwischen: dative for where something is, accusative for where it goes."
        case (.cases, _):
            "Dutch and English nouns have no cases; only pronouns change (ik/mij, I/me)."

        case (.spelling, _):
            "This word is probably misspelled or doesn't exist. Check the suggestion."

        case (.capitalization, .dutch):
            "Start sentences and names with a capital letter, including languages and nationalities (Nederlands, Engels). Days and months have no capital: maandag, januari."
        case (.capitalization, .german):
            "In German every noun has a capital letter (das Haus, die Freiheit), and so do verbs and adjectives used as nouns (das Essen, etwas Gutes). The polite Sie, Ihr and Ihnen have a capital too; du does not."
        case (.capitalization, .english):
            "Capitalise the start of a sentence, names, days, months, languages and the word I."

        case (.punctuation, .german):
            "German puts a comma before every subordinate clause: Ich weiß, dass du kommst. Also check the spaces: none before , . ! ? and one after."
        case (.punctuation, _):
            "Check the spaces and punctuation here: no space before , . ! ? and one space after."

        case (.compounds, .dutch):
            "Dutch writes compound nouns as one word, unlike English: ziekenhuisbed, fietsenstalling. Writing them apart (ziekenhuis bed) is a common mistake."
        case (.compounds, .german):
            "German writes compound nouns as one word: Krankenhausbett, Haustür, Geburtstagsfeier. Writing them apart is a common mistake."
        case (.compounds, .english):
            "Some English compounds are one word (weekend), some have a hyphen (well-known) and some are separate (living room)."

        case (.confusedWords, .dutch):
            "These words look or sound alike but mean different things. Common pairs: hun/hen, als/dan, word/wordt."
        case (.confusedWords, .german):
            "These words look or sound alike but mean different things. A common pair: das (the, which) and dass (that, joining two clauses)."
        case (.confusedWords, .english):
            "These words look or sound alike but mean different things: their/there/they're, its/it's, then/than."

        case (.style, _):
            "This isn't wrong. It's a suggestion for a more natural, shorter or clearer way to say it."

        case (.grammar, _):
            "The grammar checker found a problem here."
        }
    }

    // MARK: - Classifying LanguageTool matches

    /// Picks a topic for a LanguageTool match from its rule, category and (as a last resort) its message.
    static func classify(ruleID: String, categoryID: String?, issueType: String?,
                         message: String, language: KeyboardLanguage) -> GrammarTopic {
        if let topic = ruleTopics.first(where: { ruleID.hasPrefix($0.prefix) })?.topic { return topic }
        if let topic = topic(fromMessage: message, language: language) { return topic }
        if let categoryID, let topic = categoryTopics[categoryID] { return topic }
        switch issueType {
        case "misspelling": return .spelling
        case "style", "register": return .style
        case "typographical", "whitespace": return .punctuation
        default: return .grammar
        }
    }

    /// LanguageTool rule IDs (or ID prefixes) that clearly belong to one topic.
    static let ruleTopics: [(prefix: String, topic: GrammarTopic)] = [
        ("MORFOLOGIK_RULE", .spelling),
        ("HUNSPELL", .spelling),
        ("GERMAN_SPELLER_RULE", .spelling),
        ("EN_CONTRACTION_SPELLING", .spelling),
        ("UPPERCASE_SENTENCE_START", .capitalization),
        ("DE_CASE", .capitalization),
        ("DE_AGREEMENT", .agreement),
        ("DE_VERBAGREEMENT", .verbForms),
        ("DE_COMPOUNDS", .compounds),
        ("DAS_DASS", .confusedWords),
        ("EN_A_VS_AN", .articles),
        ("HE_VERB_AGR", .verbForms),
        ("WHITESPACE_RULE", .punctuation),
        ("COMMA_PARENTHESIS_WHITESPACE", .punctuation),
        ("DOUBLE_PUNCTUATION", .punctuation),
    ]

    static let categoryTopics: [String: GrammarTopic] = [
        "TYPOS": .spelling,
        "CASING": .capitalization,
        "PUNCTUATION": .punctuation,
        "TYPOGRAPHY": .punctuation,
        "COMPOUNDING": .compounds,
        "CONFUSED_WORDS": .confusedWords,
        "STYLE": .style,
        "REDUNDANCY": .style,
        "COLLOQUIALISMS": .style,
        "PLAIN_ENGLISH": .style,
        "GRAMMAR": .grammar,
    ]

    /// Keywords in LanguageTool's message, which is written in the language of the text.
    static func topic(fromMessage message: String, language: KeyboardLanguage) -> GrammarTopic? {
        let text = message.lowercased()
        let words = Set(text.split(whereSeparator: { !$0.isLetter && $0 != "-" }).map(String.init))
        func has(_ fragments: String...) -> Bool { fragments.contains { text.contains($0) } }
        func hasWord(_ candidates: String...) -> Bool { candidates.contains { words.contains($0) } }

        switch language {
        case .dutch:
            if has("lidwoord", "de-woord", "het-woord") { return .articles }
            if has("bijvoeglijk", "buigings") { return .adjectiveEndings }
            if has("woordvolgorde", "volgorde") { return .wordOrder }
            if has("werkwoord", "persoonsvorm", "vervoeg", "deelwoord") { return .verbForms }
            if has("congruentie", "overeenstemming") { return .agreement }
            if has("hoofdletter", "kleine letter") { return .capitalization }
            if has("aaneen", "aan elkaar", "los geschreven", "samenstelling", "koppelteken") { return .compounds }
            if has("komma", "spatie", "leesteken", "aanhalingsteken") { return .punctuation }
            if has("verwar") { return .confusedWords }
        case .german:
            if has("wortstellung", "satzstellung", "satzbau") { return .wordOrder }
            if has("kasus", "dativ", "akkusativ", "genitiv", "präposition") { return .cases }
            if has("kongruenz", "übereinstimmung") { return .agreement }
            if hasWord("artikel", "genus") { return .articles }
            if has("konjug", "partizip", "infinitiv", "personalform") || hasWord("verb", "verbs", "verben") { return .verbForms }
            if has("großschreib", "kleinschreib", "großgeschrieben", "kleingeschrieben",
                   "groß geschrieben", "klein geschrieben", "großbuchstabe") { return .capitalization }
            if has("zusammengeschrieben", "zusammenschreib", "getrennt geschrieben", "bindestrich") { return .compounds }
            if has("komma", "leerzeichen", "satzzeichen", "anführungszeichen") { return .punctuation }
            if has("verwechsl") { return .confusedWords }
        case .english:
            if has("word order") { return .wordOrder }
            if hasWord("article") { return .articles }
            if has("agreement") { return .agreement }
            if hasWord("verb", "tense", "participle") { return .verbForms }
            if has("capital", "uppercase", "lowercase") { return .capitalization }
            if has("compound", "hyphen") { return .compounds }
            if has("comma", "whitespace", "punctuation", "apostrophe") { return .punctuation }
            if has("confus") { return .confusedWords }
        }
        return nil
    }
}
