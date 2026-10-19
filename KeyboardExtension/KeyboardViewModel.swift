import UIKit
import KeyboardCore

/// The keyboard's state and actions. SwiftUI views read from it; key presses call into it.
@MainActor
final class KeyboardViewModel: ObservableObject {
    @Published private(set) var settings: TaalhulpSettings
    @Published var page: KeyboardPage = .letters
    @Published private(set) var shift: ShiftState = .off
    @Published var showsGlobe = false
    @Published private(set) var hasFullAccess = false

    private weak var controller: UIInputViewController?
    private let engine: TypingEngine
    private let store = SettingsStore()
    private let haptics = UIImpactFeedbackGenerator(style: .light)
    private var deleteRepeatTask: Task<Void, Never>?

    init(controller: UIInputViewController) {
        self.controller = controller
        self.settings = SettingsStore().load()
        self.engine = TypingEngine(document: ProxyDocument(controller: controller))
    }

    var layout: KeyboardLayout {
        KeyboardLayout.make(language: settings.currentLanguage, page: page, showsGlobe: showsGlobe)
    }

    // MARK: - Events from the controller

    func reloadSettings() {
        settings = store.load()
        hasFullAccess = controller?.hasFullAccess ?? false
        engine.autoCapitalize = settings.autoCapitalize
        engine.updateAutoCapitalization()
        syncShift()
    }

    func textDidChange() {
        engine.updateAutoCapitalization()
        syncShift()
    }

    // MARK: - Keys

    func tap(_ key: Key) {
        switch key.kind {
        case .character(let character):
            engine.type(character)
            // Like iOS: typing an apostrophe on the number page jumps back to letters.
            if character == "'" { page = .letters }
        case .shift:
            engine.shiftTapped()
        case .delete:
            break // handled by deletePressed / deleteReleased
        case .space:
            engine.space()
            if page != .letters { page = .letters }
        case .returnKey:
            engine.newline()
        case .globe:
            controller?.advanceToNextInputMode()
        case .languageSwitch:
            switchLanguage()
        case .page(let newPage):
            page = newPage
        }
        syncShift()
        feedback()
    }

    /// A long-press alternate such as é or ß was picked.
    func insertAlternate(_ text: String) {
        engine.type(text)
        syncShift()
        feedback()
    }

    /// Delete removes one character immediately, then repeats while held.
    func deletePressed() {
        engine.deleteBackward()
        syncShift()
        feedback()

        deleteRepeatTask?.cancel()
        deleteRepeatTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(450))
            while !Task.isCancelled {
                self?.engine.deleteBackward()
                self?.syncShift()
                try? await Task.sleep(for: .milliseconds(80))
            }
        }
    }

    func deleteReleased() {
        deleteRepeatTask?.cancel()
        deleteRepeatTask = nil
    }

    // MARK: - Helpers

    private func switchLanguage() {
        // Reload first so we don't overwrite changes made in the app meanwhile.
        var latest = store.load()
        latest.currentLanguage = settings.currentLanguage
        latest.currentLanguage = latest.nextLanguage()
        store.save(latest)
        settings = latest
    }

    private func syncShift() {
        if shift != engine.shift { shift = engine.shift }
    }

    private func feedback() {
        // Haptics inside a keyboard only work with Full Access.
        guard settings.hapticFeedback, hasFullAccess else { return }
        haptics.impactOccurred()
    }
}
