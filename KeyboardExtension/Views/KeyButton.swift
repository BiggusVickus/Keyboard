import SwiftUI
import KeyboardCore

/// A single key. Handles tap, hold-to-repeat (delete) and long-press accents (é, ß, ij…).
struct KeyButton: View {
    let key: Key
    let width: CGFloat
    let height: CGFloat
    /// Keys on the right half open their accent popup towards the left, so it stays on screen.
    let popupOnTrailingSide: Bool
    @ObservedObject var model: KeyboardViewModel

    @State private var isPressed = false
    @State private var showsAlternates = false
    @State private var selectedAlternate: Int?
    @State private var longPressTask: Task<Void, Never>?

    var body: some View {
        label
            .foregroundStyle(.primary)
            .frame(width: width, height: height)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(background)
                    .shadow(color: .black.opacity(0.35), radius: 0, x: 0, y: 1)
            )
            .overlay(alignment: popupOnTrailingSide ? .bottomTrailing : .bottomLeading) {
                if showsAlternates {
                    alternatesPopup
                        .offset(y: -(height + 6))
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged(touchChanged)
                    .onEnded { _ in touchEnded() }
            )
            .zIndex(showsAlternates ? 1 : 0)
    }

    // MARK: - Appearance

    @ViewBuilder
    private var label: some View {
        switch key.kind {
        case .character(let character):
            Text(display(character))
                .font(.system(size: 23))
        case .shift:
            Image(systemName: shiftSymbol)
                .font(.system(size: 18, weight: .medium))
        case .delete:
            Image(systemName: "delete.left")
                .font(.system(size: 18))
        case .space:
            Text(model.settings.currentLanguage.spaceBarLabel)
                .font(.system(size: 15))
        case .returnKey:
            Image(systemName: "return")
                .font(.system(size: 18))
        case .globe:
            Image(systemName: "globe")
                .font(.system(size: 18))
        case .languageSwitch:
            Text(model.settings.currentLanguage.shortLabel)
                .font(.system(size: 15, weight: .semibold))
        case .page(let page):
            Text(page == .letters ? "ABC" : page == .numbers ? "123" : "#+=")
                .font(.system(size: 15))
        }
    }

    private var isSpecial: Bool {
        switch key.kind {
        case .character, .space: false
        default: true
        }
    }

    private var background: Color {
        if case .shift = key.kind, model.shift != .off { return KeyColors.letter }
        if isPressed { return isSpecial ? KeyColors.letter : KeyColors.special }
        return isSpecial ? KeyColors.special : KeyColors.letter
    }

    private var shiftSymbol: String {
        switch model.shift {
        case .off: "shift"
        case .once: "shift.fill"
        case .capsLock: "capslock.fill"
        }
    }

    private func display(_ text: String) -> String {
        model.shift == .off ? text : text.uppercased()
    }

    // MARK: - Accent popup

    private var popupCellWidth: CGFloat { max(width, 32) }
    private let popupPadding: CGFloat = 4

    private var alternatesPopup: some View {
        HStack(spacing: 0) {
            ForEach(Array(key.alternates.enumerated()), id: \.offset) { index, alternate in
                Text(display(alternate))
                    .font(.system(size: 22))
                    .frame(width: popupCellWidth, height: height)
                    .foregroundStyle(index == selectedAlternate ? Color.white : Color.primary)
                    .background(
                        RoundedRectangle(cornerRadius: 5)
                            .fill(index == selectedAlternate ? Color.accentColor : Color.clear)
                    )
            }
        }
        .padding(popupPadding)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(KeyColors.letter)
                .shadow(color: .black.opacity(0.3), radius: 3)
        )
        .fixedSize()
    }

    /// Which accent is under the finger, given its x position inside the key.
    private func alternateIndex(atX x: CGFloat) -> Int {
        let count = key.alternates.count
        let popupWidth = CGFloat(count) * popupCellWidth + 2 * popupPadding
        let popupLeading = popupOnTrailingSide ? width - popupWidth : 0
        let index = Int(((x - popupLeading - popupPadding) / popupCellWidth).rounded(.down))
        return min(max(index, 0), count - 1)
    }

    // MARK: - Touch handling

    private func touchChanged(_ value: DragGesture.Value) {
        if !isPressed {
            isPressed = true
            touchBegan()
        }
        if showsAlternates {
            selectedAlternate = alternateIndex(atX: value.location.x)
        }
    }

    private func touchBegan() {
        if case .delete = key.kind {
            model.deletePressed()
            return
        }
        guard !key.alternates.isEmpty else { return }
        longPressTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            showsAlternates = true
            selectedAlternate = popupOnTrailingSide ? key.alternates.count - 1 : 0
        }
    }

    private func touchEnded() {
        longPressTask?.cancel()
        longPressTask = nil

        if case .delete = key.kind {
            model.deleteReleased()
        } else if showsAlternates, let index = selectedAlternate {
            model.insertAlternate(key.alternates[index])
        } else {
            model.tap(key)
        }

        isPressed = false
        showsAlternates = false
        selectedAlternate = nil
    }
}
