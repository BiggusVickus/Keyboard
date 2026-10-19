import SwiftUI

/// Explains how to turn the keyboard on, with a text field to try it out.
struct OnboardingView: View {
    @State private var testText = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Turn on the keyboard") {
                    step(1, "Tap **Open Settings** below.")
                    step(2, "Tap **Keyboards** and switch on **Taalhulp**.")
                    step(3, "Switch on **Allow Full Access**. This is needed for grammar checks, AI and translation.")
                    step(4, "In any app, hold the 🌐 / emoji key and choose **Taalhulp**.")

                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                }

                Section("Try it here") {
                    TextField("Typ hier iets…", text: $testText, axis: .vertical)
                        .lineLimit(3...8)
                }

                Section {
                    Text("Full Access lets the keyboard use the internet. The text near your cursor is sent to the grammar service and the AI you pick in Settings (LanguageTool, Claude, or your own local server) and nowhere else. Password fields always use Apple's keyboard, so they never reach Taalhulp.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Privacy")
                }
            }
            .navigationTitle("Taalhulp")
        }
    }

    private func step(_ number: Int, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("\(number)")
                .font(.headline)
                .foregroundStyle(.tint)
            Text(text)
        }
    }
}
