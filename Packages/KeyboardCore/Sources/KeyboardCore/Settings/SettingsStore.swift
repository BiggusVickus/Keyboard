import Foundation

/// Loads and saves `TaalhulpSettings` in the App Group, so the app and keyboard see the same values.
public struct SettingsStore {
    /// Must match the App Group in project.yml (both targets).
    public static let baseAppGroupID = "group.com.victorpiaskowski.taalhulp"

    /// The App Group this build is actually signed with. Xcode uses `baseAppGroupID`; re-signing
    /// tools for free Apple IDs (plumesign / Impactor, used by the Windows auto-refresh) append the
    /// team ID, e.g. "group.com.victorpiaskowski.taalhulp.ABCDE12345". Both the app and the keyboard
    /// get the same renamed group, so reading it from the provisioning profile keeps them in sync.
    public static let appGroupID: String = {
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url)
        else { return baseAppGroupID }
        return pickAppGroup(from: appGroups(inProvisioningProfile: data)) ?? baseAppGroupID
    }()

    /// The base group if present, else the base group with a team ID appended. Other groups the
    /// re-signer adds (one per bundle, e.g. "…taalhulp.keyboard.TEAMID") are not shared, so skip them.
    static func pickAppGroup(from groups: [String]) -> String? {
        if groups.contains(baseAppGroupID) { return baseAppGroupID }
        let prefix = baseAppGroupID + "."
        return groups.first { group in
            group.hasPrefix(prefix) && !group.dropFirst(prefix.count).contains(".")
        }
    }

    /// Reads `com.apple.security.application-groups` from an embedded.mobileprovision file
    /// (a signed container with a plain XML property list inside).
    static func appGroups(inProvisioningProfile data: Data) -> [String] {
        guard let start = data.range(of: Data("<?xml".utf8)),
              let end = data.range(of: Data("</plist>".utf8), in: start.lowerBound..<data.endIndex),
              let plist = try? PropertyListSerialization.propertyList(
                  from: data[start.lowerBound..<end.upperBound], format: nil) as? [String: Any],
              let entitlements = plist["Entitlements"] as? [String: Any]
        else { return [] }
        return entitlements["com.apple.security.application-groups"] as? [String] ?? []
    }
    static let key = "settings.v1"

    let defaults: UserDefaults

    /// Uses the shared App Group. Falls back to standard defaults if the group isn't set up
    /// (e.g. the keyboard runs without Full Access), so the keyboard still works.
    public init() {
        self.defaults = Self.sharedDefaults
    }

    /// The App Group's defaults, where all stores keep their data.
    public static var sharedDefaults: UserDefaults {
        UserDefaults(suiteName: appGroupID) ?? .standard
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
