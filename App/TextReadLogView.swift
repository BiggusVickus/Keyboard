import SwiftUI
import UIKit
import KeyboardCore

/// Settings → Diagnostics → Text reading log: what the keyboard saw, step by step, the last time
/// it read the text field (`FullText.read`). Apps differ in how much text they show a keyboard;
/// this shows exactly where reading stopped.
struct TextReadLogView: View {
    @State private var log = SettingsStore().loadTextReadLog()
    @State private var copied = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ScrollView {
            Text(log ?? "Nothing yet. In any app, use Is this correct?, Improve or the translator's Use my text, then come back here.")
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
        }
        .navigationTitle("Text reading log")
        .toolbar {
            Button(copied ? "Copied" : "Copy") {
                UIPasteboard.general.string = log
                copied = true
            }
            .disabled(log == nil)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { log = SettingsStore().loadTextReadLog(); copied = false }
        }
    }
}
