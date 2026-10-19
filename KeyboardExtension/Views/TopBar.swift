import SwiftUI
import KeyboardCore

/// The bar above the keys: the ✦ tools button, then (in order of priority)
/// suggestions for the word being typed, grammar chips, or a status line.
struct TopBar: View {
    @ObservedObject var model: KeyboardViewModel

    var body: some View {
        HStack(spacing: 4) {
            Button {
                model.openTools()
            } label: {
                Image(systemName: model.panel == .tools ? "xmark" : "sparkles")
                    .font(.system(size: 17, weight: .medium))
                    .frame(width: 38, height: 34)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tint)
            .accessibilityLabel(model.panel == .tools ? "Close tools" : "Taalhulp tools")

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.horizontal, 4)
    }

    @ViewBuilder
    private var content: some View {
        let showsSuggestions = !model.suggestions.isEmpty && (model.isTypingWord || model.issues.isEmpty)
        if let offer = model.expansionOffer {
            ExpansionBar(model: model, offer: offer)
        } else if showsSuggestions {
            SuggestionRow(model: model)
        } else if !model.issues.isEmpty {
            IssueChips(model: model)
        } else {
            StatusLine(model: model)
        }
    }
}

/// "mvg → Met vriendelijke groet,  ✕". Space or punctuation expands; tap the text to expand now,
/// or ✕ to keep the shortcut as typed.
private struct ExpansionBar: View {
    @ObservedObject var model: KeyboardViewModel
    let offer: ExpansionOffer

    var body: some View {
        HStack(spacing: 4) {
            Button {
                model.acceptExpansion()
            } label: {
                HStack(spacing: 6) {
                    Text(offer.typed)
                        .foregroundStyle(.secondary)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text(offer.text)
                        .fontWeight(.medium)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 0)
                }
                .font(.system(size: 16))
                .padding(.horizontal, 10)
                .frame(maxWidth: .infinity, minHeight: 34)
                .background(RoundedRectangle(cornerRadius: 6).fill(KeyColors.letter))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Expand \(offer.typed) to \(offer.text)")

            Button {
                model.declineExpansion()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 38, height: 34)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityLabel("Don't expand, keep \(offer.typed)")
        }
    }
}

/// Up to three suggestions, like the system keyboard.
private struct SuggestionRow: View {
    @ObservedObject var model: KeyboardViewModel

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(model.suggestions.enumerated()), id: \.element.id) { index, suggestion in
                if index > 0 {
                    Divider().frame(height: 22)
                }
                Button {
                    model.pick(suggestion)
                } label: {
                    label(for: suggestion)
                        .font(.system(size: 16))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .padding(.horizontal, 6)
                        .frame(maxWidth: .infinity, minHeight: 34)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(suggestion.isAutocorrection ? KeyColors.letter : Color.clear)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private func label(for suggestion: Suggestion) -> some View {
        switch suggestion.kind {
        case .typed:
            Text("“\(suggestion.text)”")
        case .revert:
            Label(suggestion.text, systemImage: "arrow.uturn.backward")
        case .correction, .completion:
            Text(suggestion.text)
        }
    }
}

/// Red (error) and blue (tip) chips; tap one for details.
private struct IssueChips: View {
    @ObservedObject var model: KeyboardViewModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(model.issues) { issue in
                    Button {
                        model.openIssue(issue)
                    } label: {
                        chip(for: issue)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 3)
        }
    }

    private func chip(for issue: GrammarIssue) -> some View {
        let color = KeyColors.color(for: issue.kind)
        return HStack(spacing: 5) {
            Circle().fill(color).frame(width: 7, height: 7)
            if let fix = issue.replacements.first {
                Text(issue.text).strikethrough(color: color)
                Image(systemName: "arrow.right").font(.system(size: 10, weight: .semibold))
                Text(fix).fontWeight(.medium)
            } else {
                Text(issue.text).underline(color: color)
            }
        }
        .font(.system(size: 14))
        .lineLimit(1)
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(Capsule().fill(color.opacity(0.14)))
        .accessibilityLabel("\(issue.kind == .error ? "Error" : "Tip"): \(issue.text)")
    }
}

/// Shown when there's nothing to suggest: the language, check status, or a Full Access hint.
private struct StatusLine: View {
    @ObservedObject var model: KeyboardViewModel

    var body: some View {
        HStack(spacing: 6) {
            switch model.grammarStatus {
            case .checking:
                ProgressView().controlSize(.mini)
                Text("Checking…")
            case .warning(let message):
                Image(systemName: "wifi.exclamationmark")
                Text(message)
            case .idle:
                if model.hasFullAccess {
                    Text(model.settings.currentLanguage.displayName)
                } else {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                    Text("Turn on Full Access for grammar check and AI")
                        .foregroundStyle(.orange)
                }
            }
            Spacer(minLength: 0)
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .padding(.horizontal, 6)
    }
}
