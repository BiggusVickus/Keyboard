import UIKit
import SwiftUI
import KeyboardCore

/// Entry point of the keyboard. iOS creates this when the keyboard appears.
/// It only hosts the SwiftUI keyboard and forwards events to the view model.
final class KeyboardViewController: UIInputViewController {
    private var model: KeyboardViewModel!

    /// Height of the whole keyboard including the bar above the keys.
    private let keyboardHeight: CGFloat = 270

    override func viewDidLoad() {
        super.viewDidLoad()

        model = KeyboardViewModel(controller: self)

        let host = UIHostingController(rootView: KeyboardView(model: model))
        host.view.backgroundColor = .clear
        host.view.translatesAutoresizingMaskIntoConstraints = false

        addChild(host)
        view.addSubview(host.view)
        let height = host.view.heightAnchor.constraint(equalToConstant: keyboardHeight)
        height.priority = .init(999) // avoids conflicts while iOS animates the keyboard in
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            height,
        ])
        host.didMove(toParent: self)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // Pick up changes made in the Taalhulp app since the keyboard was last shown.
        model.reloadSettings()
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        // iOS decides whether we must draw our own globe key (older iPhones, some iPads).
        model.showsGlobe = needsInputModeSwitchKey
    }

    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        model.textDidChange()
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

    func insertText(_ text: String) {
        controller?.textDocumentProxy.insertText(text)
    }

    func deleteBackward() {
        controller?.textDocumentProxy.deleteBackward()
    }
}
