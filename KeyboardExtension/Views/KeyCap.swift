import SwiftUI
import KeyboardCore

/// What every key needs from the keyboard's state. Kept small and Equatable, so a new suggestion
/// or grammar chip doesn't redraw all the keys.
struct KeyCapStyle: Equatable {
    var shift: ShiftState = .off
    var spaceLabel = ""
    var languageLabel = ""
    /// Nil shows the ⏎ symbol.
    var returnLabel: String?
    var returnProminent = false
    var returnEnabled = true
    /// While the space bar is a trackpad the key labels disappear, like on iOS.
    var hidesLabels = false
}

/// How one key looks. Touches are handled by `KeyTouchHandler` for the whole key area.
struct KeyCap: View, Equatable {
    let key: Key
    let size: CGSize
    let isPressed: Bool
    let style: KeyCapStyle

    var body: some View {
        label
            .foregroundStyle(foreground)
            .opacity(style.hidesLabels ? 0 : 1)
            .frame(width: size.width, height: size.height)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(background)
                    .shadow(color: .black.opacity(0.35), radius: 0, x: 0, y: 1)
            )
    }

    @ViewBuilder
    private var label: some View {
        switch key.kind {
        case .character(let character):
            Text(KeyCap.display(character, shift: style.shift))
                .font(.system(size: 23))
        case .shift:
            Image(systemName: shiftSymbol)
                .font(.system(size: 18, weight: .medium))
        case .delete:
            Image(systemName: "delete.left")
                .font(.system(size: 18))
        case .space:
            Text(style.spaceLabel)
                .font(.system(size: 15))
        case .returnKey:
            if let text = style.returnLabel {
                Text(text)
                    .font(.system(size: 15))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            } else {
                Image(systemName: "return")
                    .font(.system(size: 18))
            }
        case .globe:
            Image(systemName: "globe")
                .font(.system(size: 18))
        case .languageSwitch:
            Text(style.languageLabel)
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

    private var isProminentReturn: Bool {
        guard case .returnKey = key.kind else { return false }
        return style.returnProminent && style.returnEnabled
    }

    private var background: Color {
        if style.hidesLabels { return KeyColors.special.opacity(0.6) }
        if isProminentReturn { return isPressed ? KeyColors.letter : .accentColor }
        if case .shift = key.kind, style.shift != .off { return KeyColors.letter }
        // Letters show the press in the preview bubble on iPhone; elsewhere they darken.
        if isPressed, isSpecial { return KeyColors.letter }
        if isPressed, !KeyCap.showsPreviews || key.character == nil { return KeyColors.special }
        return isSpecial ? KeyColors.special : KeyColors.letter
    }

    private var foreground: Color {
        if isProminentReturn, !isPressed { return .white }
        if case .returnKey = key.kind, !style.returnEnabled { return .secondary }
        return .primary
    }

    private var shiftSymbol: String {
        switch style.shift {
        case .off: "shift"
        case .once: "shift.fill"
        case .capsLock: "capslock.fill"
        }
    }

    static func display(_ text: String, shift: ShiftState) -> String {
        shift == .off || text.hasPrefix(".") ? text : text.uppercased()
    }

    /// The bubble above a pressed letter is an iPhone thing; iPads darken the key instead.
    static let showsPreviews = UIDevice.current.userInterfaceIdiom == .phone
}

/// The bubble above a pressed letter key.
struct KeyPreview: View {
    let text: String
    let keyRect: CGRect

    var body: some View {
        Text(text)
            .font(.system(size: 30))
            .foregroundStyle(.primary)
            .frame(width: keyRect.width + 14, height: 44)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(KeyColors.letter)
                    .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
            )
            // Bottom of the bubble overlaps the top of the key a little, like iOS.
            .position(x: keyRect.midX, y: keyRect.minY + 4 - 22)
    }
}

/// The long-press popup with accents, symbols or web endings.
struct AlternatesPopupView: View {
    let popup: AlternatesPopup

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 8)
                .fill(KeyColors.letter)
                .shadow(color: .black.opacity(0.3), radius: 3)
                .frame(width: popup.frame.width, height: popup.frame.height)
                .position(x: popup.frame.midX, y: popup.frame.midY)
            ForEach(Array(popup.options.enumerated()), id: \.offset) { index, option in
                let cell = popup.cells[index]
                let selected = index == popup.selected
                Text(option)
                    .font(.system(size: option.count > 1 ? 18 : 22))
                    .foregroundStyle(selected ? Color.white : Color.primary)
                    .frame(width: cell.width, height: cell.height)
                    .background(
                        RoundedRectangle(cornerRadius: 5)
                            .fill(selected ? Color.accentColor : Color.clear)
                    )
                    .position(x: cell.midX, y: cell.midY)
            }
        }
        .allowsHitTesting(false)
    }
}
