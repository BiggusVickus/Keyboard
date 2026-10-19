import Foundation

/// One mistake the user fixed, kept so they can review what they get wrong most.
public struct LearningEntry: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var date: Date
    public var language: KeyboardLanguage
    public var topic: GrammarTopic
    /// What was typed, e.g. "het auto".
    public var original: String
    /// What it became, e.g. "de auto".
    public var corrected: String
    /// The English explanation shown at the time.
    public var explanation: String
    /// The whole sentence, for context.
    public var sentence: String

    public init(id: UUID = UUID(), date: Date = Date(), language: KeyboardLanguage, topic: GrammarTopic,
                original: String, corrected: String, explanation: String, sentence: String) {
        self.id = id
        self.date = date
        self.language = language
        self.topic = topic
        self.original = original
        self.corrected = corrected
        self.explanation = explanation
        self.sentence = sentence
    }
}

/// How often one kind of mistake was made.
public struct LearningTopicCount: Identifiable, Hashable, Sendable {
    public let language: KeyboardLanguage
    public let topic: GrammarTopic
    public let count: Int
    public let latest: LearningEntry

    public var id: String { "\(language.rawValue)-\(topic.rawValue)" }
}

/// Saves the learning log in the App Group: the keyboard writes it, the app shows it.
public struct LearningLogStore {
    static let key = "learningLog.v1"
    /// Oldest entries are dropped beyond this, to keep it small.
    public static let maxEntries = 500

    private let defaults: UserDefaults

    public init() {
        self.defaults = UserDefaults(suiteName: SettingsStore.appGroupID) ?? .standard
    }

    /// For tests.
    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    /// Newest first.
    public func load() -> [LearningEntry] {
        guard let data = defaults.data(forKey: Self.key),
              let entries = try? JSONDecoder().decode([LearningEntry].self, from: data)
        else { return [] }
        return entries
    }

    public func add(_ entry: LearningEntry) {
        var entries = load()
        // Accepting the same fix twice in a row (e.g. after an undo) counts once.
        if let last = entries.first, last.original == entry.original, last.corrected == entry.corrected,
           entry.date.timeIntervalSince(last.date) < 120 {
            return
        }
        entries.insert(entry, at: 0)
        save(Array(entries.prefix(Self.maxEntries)))
    }

    public func remove(ids: Set<UUID>) {
        save(load().filter { !ids.contains($0.id) })
    }

    public func clear() {
        defaults.removeObject(forKey: Self.key)
    }

    private func save(_ entries: [LearningEntry]) {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        defaults.set(data, forKey: Self.key)
    }

    /// Mistakes grouped by language and topic, most frequent first.
    public static func summary(of entries: [LearningEntry]) -> [LearningTopicCount] {
        let groups = Dictionary(grouping: entries) { "\($0.language.rawValue)-\($0.topic.rawValue)" }
        return groups.values.compactMap { group -> LearningTopicCount? in
            guard let latest = group.max(by: { $0.date < $1.date }) else { return nil }
            return LearningTopicCount(language: latest.language, topic: latest.topic,
                                      count: group.count, latest: latest)
        }
        .sorted { $0.count != $1.count ? $0.count > $1.count : $0.latest.date > $1.latest.date }
    }
}
