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
        host.view.backgroundColor = .clear
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

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        // iOS decides whether we must draw our own globe key (older iPhones, some iPads).
        model.showsGlobe = needsInputModeSwitchKey
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
