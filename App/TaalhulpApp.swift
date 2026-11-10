import SwiftUI
import KeyboardCore

@main
struct TaalhulpApp: App {
    @StateObject private var settings = AppSettingsModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(settings)
        }
    }
}

struct ContentView: View {
    @EnvironmentObject private var settings: AppSettingsModel
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView {
            OnboardingView()
                .tabItem { Label("Setup", systemImage: "keyboard") }
            LearnView()
                .tabItem { Label("Learn", systemImage: "graduationcap") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .onChange(of: scenePhase) { _, phase in
            // The keyboard may have changed something (e.g. the current language, learned words).
            if phase == .active { settings.reload() }
            // Keep the reinstall backup up to date with the app's and the keyboard's changes.
            KeychainBackup.save()
        }
    }
}

/// Keeps the settings in memory for SwiftUI and saves every change to the shared App Group.
@MainActor
final class AppSettingsModel: ObservableObject {
    private let store = SettingsStore()

    @Published var settings: TaalhulpSettings {
        didSet { store.save(settings) }
    }

    init() {
        // After a reinstall the App Group is empty: bring back the Keychain backup first.
        KeychainBackup.restoreIfNeeded()
        settings = SettingsStore().load()
        KeychainBackup.save()
    }

    func reload() {
        let latest = store.load()
        if latest != settings { settings = latest }
    }
}
