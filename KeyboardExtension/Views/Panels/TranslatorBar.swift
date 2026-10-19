import SwiftUI
import KeyboardCore

/// Replaces the top bar while translating. Typing goes into the box here instead of the app;
/// Insert puts the translation into the app.
struct TranslatorBar: View {
    @ObservedObject var model: KeyboardViewModel

    private var from: KeyboardLanguage { model.settings.translateFrom }
    private var to: KeyboardLanguage { model.settings.translateTo }

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                languageButton(from) { model.cycleTranslationLanguage(source: true) }
                Button(action: model.swapTranslationLanguages) {
                    Image(systemName: "arrow.left.arrow.right")
                        .frame(width: 30, height: 26)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Swap languages")
                languageButton(to) { model.cycleTranslationLanguage(source: false) }
                Spacer(minLength: 0)
                Button("Use my text", action: model.translateFieldText)
                    .font(.footnote)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                Button(action: model.closePanel) {
                    Image(systemName: "xmark")
                        .frame(width: 30, height: 26)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Close translator")
            }

            // What you're typing.
            HStack(spacing: 0) {
                if model.translatorInput.isEmpty {
                    Text("Type in \(from.englishName)…").foregroundStyle(.secondary)
                } else {
                    Text(model.translatorInput)
                }
                Rectangle().fill(.tint).frame(width: 2, height: 18)
                Spacer(minLength: 0)
            }
            .font(.callout)
            .lineLimit(2)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8).fill(KeyColors.letter))

            // The translation.
            HStack(spacing: 8) {
                result
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button("Insert", action: model.insertTranslation)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(!isLoaded)
            }
            .frame(minHeight: 40)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    private var isLoaded: Bool {
        if case .loaded = model.translation { return true }
        return false
    }

    @ViewBuilder
    private var result: some View {
        switch model.translation {
        case .idle:
            Text("The \(to.englishName) translation appears here.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        case .loading:
            ProgressView().controlSize(.small)
        case .loaded(let translation):
            VStack(alignment: .leading, spacing: 1) {
                Text(translation.translation)
                    .font(.callout.weight(.medium))
                    .lineLimit(2)
                if !translation.notes.isEmpty {
                    Text(translation.notes)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        case .failed(let message):
            Text(message)
                .font(.caption)
                .foregroundStyle(.orange)
                .lineLimit(2)
        }
    }

    private func languageButton(_ language: KeyboardLanguage, action: @escaping @MainActor () -> Void) -> some View {
        Button(action: action) {
            Text(language.shortLabel)
                .font(.footnote.weight(.semibold))
                .frame(width: 38, height: 26)
                .background(RoundedRectangle(cornerRadius: 6).fill(KeyColors.special))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(language.englishName). Tap to change.")
    }
}
