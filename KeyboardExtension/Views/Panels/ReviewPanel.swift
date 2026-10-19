import SwiftUI
import KeyboardCore

/// The AI's answer to "Is this correct?" or "Improve", with a button to use the new version.
struct ReviewPanel: View {
    @ObservedObject var model: KeyboardViewModel
    let request: ReviewRequest

    var body: some View {
        PanelCard(onClose: model.closePanel) {
            Text(request.mode == .check ? "Is this correct?" : "Improve")
                .font(.subheadline.weight(.semibold))
            if case .loaded(let result) = model.review, request.mode == .check {
                Badge(text: result.isCorrect ? "Correct" : "Not quite",
                      color: result.isCorrect ? .green : KeyColors.error)
            }
        } content: {
            switch model.review {
            case .idle, .loading:
                if let span = request.span {
                    Text("“\(span.text)”").font(.callout).foregroundStyle(.secondary).lineLimit(2)
                }
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Asking \(model.settings.aiProvider.title)…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            case .failed(let message):
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            case .loaded(let result):
                resultView(result)
            }
        } actions: {
            if case .loaded(let result) = model.review, result.revised != request.span?.text {
                Button("Use this") { model.useRevision(result, for: request) }
                    .buttonStyle(.borderedProminent)
            }
            Spacer(minLength: 0)
            Button("Done", action: model.closePanel)
                .buttonStyle(.bordered)
        }
        .controlSize(.small)
    }

    @ViewBuilder
    private func resultView(_ result: SentenceReview) -> some View {
        Text(result.summary)
            .font(.callout.weight(.medium))
            .fixedSize(horizontal: false, vertical: true)

        if result.revised != request.span?.text {
            Text(result.revised)
                .font(.callout)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 6).fill(KeyColors.letter))
                .fixedSize(horizontal: false, vertical: true)
        }

        ForEach(Array(result.changes.enumerated()), id: \.offset) { _, change in
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(change.original).strikethrough()
                    Image(systemName: "arrow.right").font(.caption2)
                    Text(change.replacement).fontWeight(.semibold)
                    if change.optional {
                        Badge(text: "optional", color: KeyColors.tip)
                    }
                }
                .font(.caption)
                Text(change.explanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
