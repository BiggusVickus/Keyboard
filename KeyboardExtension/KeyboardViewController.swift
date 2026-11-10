import UIKit
import SwiftUI
import KeyboardCore

/// Entry point of the keyboard. iOS creates this when the keyboard appears.
/// It only hosts the SwiftUI keyboard and forwards events to the view model.
final class KeyboardViewController: UIInputViewController {
    private var model: KeyboardViewModel!
    private var host: UIHostingController<KeyboardView>!
    private var heightConstraint: NSLayoutConstraint!

    override func viewDidLoad() {
        super.viewDidLoad()

        model = KeyboardViewModel(controller: self)
        model.onPanelChange = { [weak self] panel in
            self?.heightConstraint.constant = KeyboardView.height(for: panel)
        }

        host = UIHostingController(rootView: KeyboardView(model: model))
        // Not .clear: iOS drops taps on fully transparent parts of a keyboard, so the space between
        // suggestions, buttons and keys would ignore taps. 1 % white is invisible but receives them.
        host.view.backgroundColor = UIColor(white: 1, alpha: 0.01)
        host.view.translatesAutoresizingMaskIntoConstraints = false

        addChild(host)
        view.addSubview(host.view)
        heightConstraint = host.view.heightAnchor.constraint(equalToConstant: KeyboardView.height(for: .none))
        heightConstraint.priority = .init(999) // avoids conflicts while iOS animates the keyboard in
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            heightConstraint,
        ])
        host.didMove(toParent: self)

        // Names from Contacts (so they aren't "corrected") and the user's text replacements.
        requestSupplementaryLexicon { [weak self] lexicon in
            Task { @MainActor in self?.model.useLexicon(lexicon) }
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // Pick up changes made in the Taalhulp app since the keyboard was last shown.
        model.reloadSettings()
        updateAppearance()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // iPhones with a home indicator always show the system globe and mic below the keyboard,
        // so there's no need to ask (asking this early logs "called before a connection was established").
        if UIDevice.current.userInterfaceIdiom == .phone, (view.window?.safeAreaInsets.bottom ?? 0) > 0 {
            if model.showsGlobe { model.showsGlobe = false }
            return
        }
        // Elsewhere (Home-button iPhones, iPads), ask once the connection to the app is set up.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.updateGlobeKey() }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        model.touches.reset()
    }

    /// iOS decides whether we must draw our own globe key (older iPhones, some iPads). It only knows
    /// once the keyboard is connected to the app, so ask once per appearance, after appearing.
    /// Not during layout or in `textDidChange`: iOS calls those while still connecting, which logs
    /// "needsInputModeSwitchKey was called before a connection was established".
    private func updateGlobeKey() {
        guard let model else { return }
        let needed = needsInputModeSwitchKey
        if model.showsGlobe != needed { model.showsGlobe = needed }
    }

    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        guard let model else { return }  // iOS can call this before the view has loaded
        model.textDidChange()
        updateAppearance()
    }

    /// Some apps ask for a dark keyboard even in light mode (and the other way round).
    private func updateAppearance() {
        guard let host else { return }
        let style: UIUserInterfaceStyle
        switch textDocumentProxy.keyboardAppearance ?? .default {
        case .dark: style = .dark
        case .light: style = .light
        default: style = .unspecified
        }
        if host.overrideUserInterfaceStyle != style { host.overrideUserInterfaceStyle = style }
    }
}

/// Lets the platform-independent `TypingEngine` talk to the real text field.
final class ProxyDocument: TextDocument {
    private weak var controller: UIInputViewController?

    init(controller: UIInputViewController) {
        self.controller = controller
    }

    var documentContextBeforeInput: String? {
        controller?.textDocumentProxy.documentContextBeforeInput
    }

    var documentContextAfterInput: String? {
        controller?.textDocumentProxy.documentContextAfterInput
    }

    var selectedText: String? {
        controller?.textDocumentProxy.selectedText
    }

    func insertText(_ text: String) {
        controller?.textDocumentProxy.insertText(text)
    }

    func deleteBackward() {
        controller?.textDocumentProxy.deleteBackward()
    }

    func adjustTextPosition(byCharacterOffset offset: Int) {
        controller?.textDocumentProxy.adjustTextPosition(byCharacterOffset: offset)
    }
}
