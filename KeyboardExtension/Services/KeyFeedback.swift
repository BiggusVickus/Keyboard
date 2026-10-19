import UIKit
import AudioToolbox
import KeyboardCore

/// Key sounds and haptics, played the moment a finger touches a key (like the system keyboard),
/// not when it is lifted.
@MainActor
final class KeyFeedback {
    /// The iOS keyboard's own sounds. Like the system keyboard, they follow the silent switch.
    enum Sound: SystemSoundID {
        /// Letters, numbers and symbols.
        case click = 1104
        /// Delete (also on every repeat while held).
        case delete = 1155
        /// Shift, space, return, 123, globe, language.
        case modifier = 1156
    }

    var soundsEnabled = true
    var hapticsEnabled = true
    /// Keyboards can only play sounds and haptics with Full Access.
    var hasFullAccess = false

    private let impact = UIImpactFeedbackGenerator(style: .light)
    private let selection = UISelectionFeedbackGenerator()
    private let trackpadImpact = UIImpactFeedbackGenerator(style: .medium)

    /// Wakes the haptic engine so the first tap isn't late. Call when the keyboard appears and on touch down.
    func prepare() {
        guard hapticsEnabled, hasFullAccess else { return }
        impact.prepare()
    }

    func keyDown(_ kind: Key.Kind) {
        play(Self.sound(for: kind))
        if hapticsEnabled, hasFullAccess {
            impact.impactOccurred()
            impact.prepare()
        }
    }

    /// Each repeat of a held delete key.
    func deleteRepeat() {
        play(.delete)
    }

    /// The space bar turned into a trackpad.
    func trackpadStarted() {
        guard hapticsEnabled, hasFullAccess else { return }
        trackpadImpact.impactOccurred()
        selection.prepare()
    }

    /// The cursor moved one step on the trackpad.
    func cursorStep() {
        play(.click)
        if hapticsEnabled, hasFullAccess {
            selection.selectionChanged()
            selection.prepare()
        }
    }

    /// Taps outside the keys (suggestions, chips, panel buttons).
    func buttonTap() {
        guard hapticsEnabled, hasFullAccess else { return }
        impact.impactOccurred()
    }

    private func play(_ sound: Sound) {
        guard soundsEnabled, hasFullAccess else { return }
        AudioServicesPlaySystemSound(sound.rawValue)
    }

    static func sound(for kind: Key.Kind) -> Sound {
        switch kind {
        case .character: .click
        case .delete: .delete
        case .shift, .space, .returnKey, .globe, .languageSwitch, .page: .modifier
        }
    }
}
