import Foundation

/// A copy of everything worth keeping (settings, text expansions, touch map, learned words,
/// learning log), so a reinstall doesn't start from zero.
///
/// The App Group container is deleted when the app is removed, and a build signed differently
/// (Xcode vs. the Windows refresh, which renames the group) gets a new, empty one. The app keeps
/// this snapshot in its Keychain, which iOS keeps across reinstalls, and puts it back into a
/// fresh container (see App/KeychainBackup.swift).
public enum SettingsBackup {
    /// What is backed up. The keyboard report is left out: it describes the keyboard that runs now.
    public static let keys = [SettingsStore.key, TouchProfileStore.key, LearnedWordsStore.key, LearningLogStore.key]

    /// Set in the App Group once its data is ours. Missing = a fresh container: restore into it.
    static let markerKey = "backup.containerInitialized.v1"

    /// The backed-up values as a property list, or nil when there is nothing to back up.
    public static func snapshot(of defaults: UserDefaults) -> Data? {
        var values: [String: Any] = [:]
        for key in keys {
            if let value = defaults.object(forKey: key) { values[key] = value }
        }
        guard !values.isEmpty else { return nil }
        return try? PropertyListSerialization.data(fromPropertyList: values, format: .binary, options: 0)
    }

    /// Call when the app starts, before reading any settings. In a fresh container, puts the
    /// backup back (replacing whatever the keyboard may have saved there first). Returns the keys
    /// that were restored; empty when the container already had our data or there was no backup.
    @discardableResult
    public static func restoreIfFresh(from backup: Data?, into defaults: UserDefaults) -> [String] {
        guard !defaults.bool(forKey: markerKey) else { return [] }
        defaults.set(true, forKey: markerKey)
        guard let backup,
              let values = try? PropertyListSerialization.propertyList(from: backup, format: nil) as? [String: Any]
        else { return [] }
        var restored: [String] = []
        for key in keys {
            if let value = values[key] {
                defaults.set(value, forKey: key)
                restored.append(key)
            }
        }
        return restored
    }
}
