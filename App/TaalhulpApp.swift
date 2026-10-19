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
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .onChange(of: scenePhase) { _, phase in
            // The keyboard may have changed something (e.g. the current language).
            if phase == .active { settings.reload() }
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
        settings = SettingsStore().load()
    }

    func reload() {
        let latest = store.load()
        if latest != settings { settings = latest }
    }
}
