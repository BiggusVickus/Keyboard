import SwiftUI
import KeyboardCore

/// The ✦ menu: ask the AI whether a sentence is correct, improve it, or open the translator.
struct ToolsPanel: View {
    @ObservedObject var model: KeyboardViewModel

    var body: some View {
        PanelCard(onClose: model.closePanel) {
            Text("Taalhulp")
                .font(.subheadline.weight(.semibold))
        } content: {
            if let sentence = model.currentSentence {
                Text("“\(sentence)”")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            } else {
                Text("Type a sentence, then check or improve it here. The translator works on its own text.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            if model.settings.aiProvider == .none {
                Text("These tools need an AI helper. Choose one in the Taalhulp app (Settings → AI helper).")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        } actions: {
            tool("Is this correct?", systemImage: "checkmark.bubble") { model.startReview(.check) }
            tool("Improve", systemImage: "wand.and.stars") { model.startReview(.improve) }
            tool("Translate", systemImage: "character.bubble") { model.openTranslator() }
        }
    }

    private func tool(_ title: String, systemImage: String, action: @escaping @MainActor () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.system(size: 20))
                Text(title)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(RoundedRectangle(cornerRadius: 8).fill(KeyColors.letter))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
