import SwiftUI

/// The frame shared by all panels that replace the keys: a title row with a close button,
/// scrollable content, and a row of buttons at the bottom.
struct PanelCard<Header: View, Content: View, Actions: View>: View {
    let onClose: @MainActor () -> Void
    @ViewBuilder let header: Header
    @ViewBuilder let content: Content
    @ViewBuilder let actions: Actions

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                header
                Spacer(minLength: 0)
                Button(action: onClose) {
                    Image(systemName: "keyboard.chevron.compact.down")
                        .font(.system(size: 16))
                        .frame(width: 34, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Back to keyboard")
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    content
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(spacing: 8) {
                actions
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 10).fill(KeyColors.panel))
    }
}

/// A small coloured label such as "Error" or "Tip · optional".
struct Badge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.15)))
    }
}
