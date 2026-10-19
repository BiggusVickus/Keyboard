import SwiftUI
import KeyboardCore

/// Details of one grammar issue: what's wrong in English, the fixes, Explain (AI) and Ignore.
struct IssuePanel: View {
    @ObservedObject var model: KeyboardViewModel
    let issue: GrammarIssue

    private var language: KeyboardLanguage { model.settings.currentLanguage }
    private var color: Color { KeyColors.color(for: issue.kind) }

    var body: some View {
        PanelCard(onClose: model.closePanel) {
            Badge(text: issue.kind == .error ? "Error" : "Tip · optional", color: color)
            Text(issue.topic.title(for: language))
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
        } content: {
            HStack(spacing: 6) {
                Text(issue.text).strikethrough(color: color)
                if let fix = issue.replacements.first {
                    Image(systemName: "arrow.right").font(.caption)
                    Text(fix).fontWeight(.semibold)
                }
            }
            .font(.callout)

            Text(issue.englishExplanation(language: language))
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)

            if issue.source == .languageTool, language != .english {
                Text("LanguageTool: \(issue.message)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            aiExplanation
        } actions: {
            ForEach(issue.replacements.prefix(2), id: \.self) { replacement in
                Button {
                    model.accept(issue, replacement: replacement)
                } label: {
                    Text(replacement).lineLimit(1)
                }
                .buttonStyle(.borderedProminent)
                .tint(color)
            }
            Spacer(minLength: 0)
            if model.settings.aiProvider != .none, model.explanation == .idle {
                Button("Explain") { model.explainWithAI(issue) }
                    .buttonStyle(.bordered)
            }
            Button("Ignore") { model.ignore(issue) }
                .buttonStyle(.bordered)
        }
        .controlSize(.small)
    }

    @ViewBuilder
    private var aiExplanation: some View {
        switch model.explanation {
        case .idle:
            EmptyView()
        case .loading:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Asking \(model.settings.aiProvider.title)…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .loaded(let text):
            VStack(alignment: .leading, spacing: 2) {
                Label(model.settings.aiProvider.title, systemImage: "sparkles")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tint)
                Text(text)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .failed(let message):
            Text(message)
                .font(.caption)
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
