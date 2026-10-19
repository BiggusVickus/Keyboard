import Foundation

/// Loads and saves `TaalhulpSettings` in the App Group, so the app and keyboard see the same values.
public struct SettingsStore {
    /// Must match the App Group in project.yml (both targets).
    public static let appGroupID = "group.com.victor.taalhulp"
    static let key = "settings.v1"

    private let defaults: UserDefaults

    /// Uses the shared App Group. Falls back to standard defaults if the group isn't set up
    /// (e.g. the keyboard runs without Full Access), so the keyboard still works.
    public init() {
        self.defaults = UserDefaults(suiteName: Self.appGroupID) ?? .standard
    }

    /// For tests.
    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    public func load() -> TaalhulpSettings {
        guard let data = defaults.data(forKey: Self.key),
              let settings = try? JSONDecoder().decode(TaalhulpSettings.self, from: data)
        else { return TaalhulpSettings() }
        return settings
    }

    public func save(_ settings: TaalhulpSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: Self.key)
    }
}
