import SwiftUI
import KeyboardCore

/// The whole keyboard: the bar on top (later: suggestions + grammar) and the key rows.
struct KeyboardView: View {
    @ObservedObject var model: KeyboardViewModel

    static let keySpacing: CGFloat = 6
    static let rowSpacing: CGFloat = 11
    static let keyHeight: CGFloat = 43

    var body: some View {
        VStack(spacing: 0) {
            TopBar(model: model)
                .frame(height: 40)
            keyRows
                .padding(.horizontal, 3)
                .padding(.bottom, 4)
        }
    }

    private var keyRows: some View {
        let layout = model.layout
        let rowCount = CGFloat(layout.rows.count)
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
        .frame(height: rowCount * Self.keyHeight + (rowCount - 1) * Self.rowSpacing)
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

/// The bar above the keys. For now it shows the language and a Full Access warning;
/// autocorrect suggestions and grammar chips will live here (milestones 2 and 3).
struct TopBar: View {
    @ObservedObject var model: KeyboardViewModel

    var body: some View {
        HStack {
            if model.hasFullAccess {
                Text(model.settings.currentLanguage.displayName)
                    .foregroundStyle(.secondary)
            } else {
                Label("Turn on Full Access for grammar help", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            }
            Spacer()
        }
        .font(.footnote)
        .padding(.horizontal, 12)
    }
}

/// Key colours that match the system keyboard in light and dark mode.
enum KeyColors {
    static let letter = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(white: 0.42, alpha: 1) : .white
    })
    static let special = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(white: 0.27, alpha: 1)
            : UIColor(red: 0.67, green: 0.69, blue: 0.73, alpha: 1)
    })
}
