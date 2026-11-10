import Foundation
import Security
import KeyboardCore

/// Keeps `SettingsBackup` in the app's Keychain. Keychain items stay on the iPhone when the app
/// is deleted or re-signed (as long as it's the same Apple ID and bundle ID), unlike the App Group,
/// so settings, the trained touch map, learned words and the learning log come back after a reinstall.
enum KeychainBackup {
    private static let service = "com.victorpiaskowski.taalhulp.backup"
    private static let account = "settings"

    /// Puts the backup into a fresh App Group. Call before anything reads the settings.
    static func restoreIfNeeded() {
        let restored = SettingsBackup.restoreIfFresh(from: read(), into: SettingsStore.sharedDefaults)
        if !restored.isEmpty { print("Restored from Keychain backup: \(restored.joined(separator: ", "))") }
    }

    /// Saves the current App Group data (including what the keyboard learned since last time).
    static func save() {
        guard let data = SettingsBackup.snapshot(of: SettingsStore.sharedDefaults), data != read() else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            status = SecItemAdd(query.merging(attributes) { $1 } as CFDictionary, nil)
        }
        if status != errSecSuccess { print("Keychain backup failed: \(status)") }
    }

    private static func read() -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }
}
