import Foundation

/// What the keyboard last reported to the app: which build it runs and which touch map it uses.
/// iOS sometimes keeps running an old keyboard after a new install, and nothing on screen shows
/// that; with this, Settings → Touch map can tell you.
public struct KeyboardReport: Codable, Equatable, Sendable {
    /// When the keyboard last opened.
    public var date: Date
    /// When the keyboard's program file was built/installed (see `BuildInfo`).
    public var build: Date?
    public var touchModel: TouchModelKind
    /// Trained taps the keyboard loaded (0 unless the touch map is Custom).
    public var trainedTaps: Int

    public init(date: Date = Date(), build: Date?, touchModel: TouchModelKind, trainedTaps: Int) {
        self.date = date
        self.build = build
        self.touchModel = touchModel
        self.trainedTaps = trainedTaps
    }

    /// The keyboard's build is clearly older than the app's: both are installed together, so
    /// more than 10 minutes apart means iOS is still running an earlier keyboard.
    public func isOutdated(comparedTo appBuild: Date?) -> Bool {
        guard let build, let appBuild else { return false }
        return appBuild.timeIntervalSince(build) > 600
    }
}

public enum BuildInfo {
    /// Modification date of the running program's executable: changes with every build and install.
    public static let executableDate: Date? = {
        guard let path = Bundle.main.executablePath,
              let attributes = try? FileManager.default.attributesOfItem(atPath: path)
        else { return nil }
        return attributes[.modificationDate] as? Date
    }()
}

extension SettingsStore {
    static let reportKey = "keyboardReport.v1"

    /// Written by the keyboard each time it opens (needs Full Access to reach the app).
    public func saveKeyboardReport(_ report: KeyboardReport) {
        guard let data = try? JSONEncoder().encode(report) else { return }
        defaults.set(data, forKey: Self.reportKey)
    }

    public func loadKeyboardReport() -> KeyboardReport? {
        guard let data = defaults.data(forKey: Self.reportKey) else { return nil }
        return try? JSONDecoder().decode(KeyboardReport.self, from: data)
    }
}
