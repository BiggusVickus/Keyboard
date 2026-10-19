import SwiftUI
import KeyboardCore

/// The whole keyboard: the bar on top (suggestions, grammar chips, or the translator)
/// and below it the key rows, or a panel with grammar details or AI results.
struct KeyboardView: View {
    @ObservedObject var model: KeyboardViewModel

    static let keySpacing: CGFloat = 6
    static let rowSpacing: CGFloat = 11
    static let keyHeight: CGFloat = 43
    static let topBarHeight: CGFloat = 40
    static let translatorBarHeight: CGFloat = 136
    static let bottomPadding: CGFloat = 4
    /// Four rows of keys. Panels get exactly this much room, so the keyboard never jumps.
    static let keyAreaHeight: CGFloat = 4 * keyHeight + 3 * rowSpacing

    /// Total height for the controller's constraint.
    static func height(for panel: Panel) -> CGFloat {
        (panel == .translator ? translatorBarHeight : topBarHeight) + keyAreaHeight + bottomPadding
    }

    var body: some View {
        VStack(spacing: 0) {
            if model.isTranslating {
                TranslatorBar(model: model)
                    .frame(height: Self.translatorBarHeight)
            } else {
                TopBar(model: model)
                    .frame(height: Self.topBarHeight)
            }
            keyArea
                .frame(height: Self.keyAreaHeight)
                .padding(.horizontal, 3)
                .padding(.bottom, Self.bottomPadding)
        }
    }

    @ViewBuilder
    private var keyArea: some View {
        switch model.panel {
        case .none, .translator:
            keyRows
        case .issue(let issue):
            IssuePanel(model: model, issue: issue)
        case .tools:
            ToolsPanel(model: model)
        case .review(let request):
            ReviewPanel(model: model, request: request)
        }
    }

    private var keyRows: some View {
        let layout = model.layout
        // All letter keys get the same width, based on the row with the most letters.
        let maxCharacters = CGFloat(layout.rows.map { $0.filter { $0.character != nil }.count }.max() ?? 10)

        return GeometryReader { geo in
            let unit = (geo.size.width - Self.keySpacing * (maxCharacters - 1)) / maxCharacters
            VStack(spacing: Self.rowSpacing) {
                ForEach(Array(layout.rows.enumerated()), id: \.offset) { _, row in
                    let widths = Self.widths(for: row, unit: unit, total: geo.size.width)
                    HStack(spacing: Self.keySpacing) {
                        ForEach(Array(row.enumerated()), id: \.element.id) { index, key in
                            KeyButton(
                                key: key,
                                width: widths[index],
                                height: Self.keyHeight,
                                popupOnTrailingSide: index >= row.count / 2,
                                model: model
                            )
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    /// Letter keys are `unit` wide; special keys (shift, delete, space…) share the space left over,
    /// in proportion to their `width`. A row with only letters is simply centred.
    static func widths(for row: [Key], unit: CGFloat, total: CGFloat) -> [CGFloat] {
        let characterCount = row.filter { $0.character != nil }.count
        let specialWeight = row.filter { $0.character == nil }.reduce(0.0) { $0 + $1.width }
        guard specialWeight > 0 else { return row.map { _ in unit } }

        let used = CGFloat(characterCount) * unit + keySpacing * CGFloat(row.count - 1)
        let perWeight = max(0, total - used) / CGFloat(specialWeight)
        return row.map { $0.character != nil ? unit : perWeight * CGFloat($0.width) }
    }
}

/// Colours that match the system keyboard in light and dark mode.
enum KeyColors {
    static let letter = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(white: 0.42, alpha: 1) : .white
    })
    static let special = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(white: 0.27, alpha: 1)
            : UIColor(red: 0.67, green: 0.69, blue: 0.73, alpha: 1)
    })
    /// Cards and panels that sit where the keys normally are.
    static let panel = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(white: 0.20, alpha: 1) : UIColor(white: 0.98, alpha: 1)
    })
    static let error = Color(UIColor.systemRed)
    static let tip = Color(UIColor.systemBlue)

    static func color(for kind: GrammarIssue.Kind) -> Color {
        kind == .error ? error : tip
    }
}
