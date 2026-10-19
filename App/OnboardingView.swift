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

                Section("How it works") {
                    tip("text.word.spacing", "The bar above the keys suggests words. Press space to accept a highlighted fix; tap the ↩︎ word to undo it.")
                    tip("exclamationmark.bubble", "Red chips are errors, blue chips are optional tips. Tap one for an English explanation and the fix.")
                    tip("sparkles", "The ✦ button asks the AI \"Is this correct?\", improves a sentence, or opens the translator.")
                    tip("graduationcap", "Every fix you accept is saved in Learn, so you can see what to practise.")
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

                Section {
                    Text("The offline de/het check uses words from Wiktionary (Dutch and English editions), © Wiktionary contributors, CC BY-SA 4.0, extracted by kaikki.org / wiktextract.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Link("Licence: CC BY-SA 4.0", destination: URL(string: "https://creativecommons.org/licenses/by-sa/4.0/")!)
                        .font(.footnote)
                } header: {
                    Text("Credits")
                }
            }
            .navigationTitle("Taalhulp")
        }
    }

    private func tip(_ systemImage: String, _ text: LocalizedStringKey) -> some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: systemImage).foregroundStyle(.tint)
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
