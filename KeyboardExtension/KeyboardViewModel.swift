import UIKit
import os
import KeyboardCore

/// Something that is loading, done, or failed (AI answers, translations).
enum LoadState<Value: Equatable>: Equatable {
    case idle
    case loading
    case loaded(Value)
    case failed(String)
}

/// What is shown instead of (or on top of) the keys.
enum Panel: Equatable {
    case none
    /// Details of one grammar issue, with Accept / Explain / Ignore.
    case issue(GrammarIssue)
    /// The ✦ menu: Is this correct?, Improve, Translate.
    case tools
    /// The AI's answer to "Is this correct?" or "Improve".
    case review(ReviewRequest)
    /// The translator bar above the keys; typing goes into it instead of the app.
    case translator
}

/// A shortcut you typed and what it will become.
struct ExpansionOffer: Equatable {
    let typed: String
    let text: String
}

struct ReviewRequest: Equatable {
    enum Mode: Equatable {
        case check
        case improve
    }

    let mode: Mode
    /// The sentence being reviewed and where it was in the text. Nil when there was nothing to review.
    let span: TextSpan?
}

enum GrammarStatus: Equatable {
    case idle
    case checking
    /// LanguageTool couldn't be used; the text says why.
    case warning(String)
}

/// The keyboard's state and actions. SwiftUI views read from it; key presses call into it.
@MainActor
final class KeyboardViewModel: ObservableObject {
    @Published private(set) var settings: TaalhulpSettings
    @Published var page: KeyboardPage = .letters
    @Published private(set) var shift: ShiftState = .off
    @Published var showsGlobe = false
    @Published private(set) var hasFullAccess = false
    @Published private(set) var traits = FieldTraits()
    @Published private(set) var hasText = false

    // Suggestion bar (milestone 2)
    @Published private(set) var suggestions: [Suggestion] = []
    @Published private(set) var isTypingWord = false
    /// Your own shortcut (Settings → Text expansions) matches the word being typed. Shown above the
    /// keys; space or punctuation expands it unless you tap ✕ first.
    @Published private(set) var expansionOffer: ExpansionOffer?

    // Grammar (milestones 3–4)
    @Published private(set) var issues: [GrammarIssue] = []
    @Published private(set) var grammarStatus: GrammarStatus = .idle

    // Panels and AI (milestone 4b)
    @Published private(set) var panel: Panel = .none
    @Published private(set) var explanation: LoadState<String> = .idle
    @Published private(set) var review: LoadState<SentenceReview> = .idle

    // Translator (milestone 5)
    @Published private(set) var translatorInput = ""
    @Published private(set) var translation: LoadState<Translation> = .idle

    /// Called when the keyboard needs a different height (the translator is taller).
    var onPanelChange: ((Panel) -> Void)?

    /// Touches on the key area. Separate from the model so a key press only redraws the keys.
    private(set) lazy var touches = KeyTouchHandler(model: self)
    let feedback = KeyFeedback()

    private weak var controller: UIInputViewController?
    private let proxy: ProxyDocument
    private let engine: TypingEngine
    private let buffer: TextBuffer
    private let bufferEngine: TypingEngine
    private let store = SettingsStore()
    private let learnedWordsStore = LearnedWordsStore()
    private let learningLog = LearningLogStore()
    private let spellChecker: SystemSpellChecker
    private let autocorrector: Autocorrector
    private let grammarChecker = GrammarChecker()
    private let touchProfileStore = TouchProfileStore()

    private var lastAutocorrection: Autocorrection?
    /// The shortcut you tapped ✕ on; it stays as typed until you start another word.
    private var declinedExpansionWord: String?
    private var grammarResult: GrammarResult?
    private var ignoredIssues: Set<String> = []
    /// When translating text from the field, where that text was (so Insert can replace it).
    private var translationSource: TextSpan?

    private var deleteRepeatTask: Task<Void, Never>?
    private var grammarTask: Task<Void, Never>?
    private var aiTask: Task<Void, Never>?
    private var translateTask: Task<Void, Never>?
    /// Suggestions and grammar are refreshed just after a key press is drawn, not before.
    private var textAnalysisPending = false
    private var cachedLayout: (key: LayoutKey, layout: KeyboardLayout)?

    private struct LayoutKey: Equatable {
        let language: KeyboardLanguage
        let page: KeyboardPage
        let showsGlobe: Bool
        let field: FieldKind
    }

    private static let log = Logger(subsystem: "Taalhulp.keyboard", category: "keyboard")

    /// Characters after which the word before them is autocorrected, like the system keyboard.
    private static let wordEndingPunctuation: Set<String> = [".", ",", "!", "?", ";", ":"]

    init(controller: UIInputViewController) {
        self.controller = controller
        self.settings = SettingsStore().load()
        let proxy = ProxyDocument(controller: controller)
        let buffer = TextBuffer()
        let spellChecker = SystemSpellChecker()
        self.proxy = proxy
        self.engine = TypingEngine(document: proxy)
        self.buffer = buffer
        self.bufferEngine = TypingEngine(document: buffer)
        self.spellChecker = spellChecker
        self.autocorrector = Autocorrector(checker: spellChecker)
    }

    // MARK: - What the views show

    var isTranslating: Bool { panel == .translator }

    /// The translator types in its source language; otherwise the keyboard's current language.
    var layoutLanguage: KeyboardLanguage {
        isTranslating ? settings.translateFrom : settings.currentLanguage
    }

    var layout: KeyboardLayout {
        let key = LayoutKey(language: layoutLanguage, page: page, showsGlobe: showsGlobe,
                            field: isTranslating ? .text : traits.kind)
        if let cachedLayout, cachedLayout.key == key { return cachedLayout.layout }
        let layout = KeyboardLayout.make(language: key.language, page: key.page, showsGlobe: key.showsGlobe,
                                         field: key.field)
        cachedLayout = (key, layout)
        return layout
    }

    func keyCapStyle(trackpad: Bool) -> KeyCapStyle {
        KeyCapStyle(
            shift: shift,
            spaceLabel: layoutLanguage.spaceBarLabel,
            languageLabel: layoutLanguage.shortLabel,
            returnLabel: isTranslating ? "Translate" : traits.returnKey.label(for: layoutLanguage),
            returnProminent: isTranslating || traits.returnKey.isProminent,
            returnEnabled: returnKeyEnabled,
            hidesLabels: trackpad
        )
    }

    /// Holding the space bar moves the cursor (not in the translator, which has its own text).
    var trackpadAvailable: Bool { !isTranslating }

    var returnKeyEnabled: Bool {
        isTranslating || !traits.enablesReturnKeyAutomatically || hasText
    }

    /// The sentence the tools would work on, for the preview in the tools panel.
    var currentSentence: String? {
        TextEditing.currentSentence(before: context)?.text
    }

    private var context: String { proxy.documentContextBeforeInput ?? "" }
    private var activeEngine: TypingEngine { isTranslating ? bufferEngine : engine }
    private var languageHelpAllowed: Bool { traits.wantsLanguageHelp && !isTranslating }
    private var grammarAllowed: Bool { languageHelpAllowed && settings.grammarCheckEnabled }

    // MARK: - Events from the controller

    func reloadSettings() {
        settings = store.load()
        hasFullAccess = controller?.hasFullAccess ?? false
        engine.autoCapitalize = settings.autoCapitalize
        bufferEngine.autoCapitalize = settings.autoCapitalize
        autocorrector.mode = settings.autocorrect
        autocorrector.language = settings.currentLanguage
        autocorrector.learnedWords = learnedWordsStore.load()
        feedback.hapticsEnabled = settings.hapticFeedback
        feedback.soundsEnabled = settings.keySounds
        feedback.hasFullAccess = hasFullAccess
        feedback.prepare()
        let profile = settings.touchModel == .custom ? touchProfileStore.load() : nil
        touches.hitTester = KeyHitTester(kind: settings.touchModel, profile: profile)
        reportToApp(trainedTaps: profile?.samples.count ?? 0)
        grammarResult = nil
        updateTraits()
        engine.updateAutoCapitalization()
        syncShift()
        // Suggestions need the spell checker, whose first use loads a dictionary. Do it just after
        // the keyboard is on screen instead of holding up its first frame.
        scheduleTextAnalysis()
    }

    func textDidChange() {
        updateTraits()
        engine.updateAutoCapitalization()
        syncShift()
        // Coalesced with the update scheduled by the key press itself.
        if !isTranslating { scheduleTextAnalysis() }
    }

    /// Contacts and text shortcuts from iOS (Settings → General → Keyboard → Text Replacement).
    func useLexicon(_ lexicon: UILexicon) {
        var names: Set<String> = []
        var shortcuts: [String: String] = [:]
        for entry in lexicon.entries {
            if entry.userInput == entry.documentText {
                names.insert(entry.documentText.lowercased())
            } else {
                shortcuts[entry.userInput.lowercased()] = entry.documentText
            }
        }
        spellChecker.extraWords = names
        autocorrector.shortcuts = shortcuts
    }

    /// Reads what the text field wants: return key, e-mail/URL keys, capitalisation…
    private func updateTraits() {
        guard let proxy = controller?.textDocumentProxy else { return }
        let newTraits = FieldTraits(
            kind: Self.fieldKind(proxy.keyboardType ?? .default),
            returnKey: Self.returnKeyStyle(proxy.returnKeyType ?? .default),
            capitalization: Self.capitalization(proxy.autocapitalizationType ?? .sentences),
            allowsAutocorrection: (proxy.autocorrectionType ?? .default) != .no,
            enablesReturnKeyAutomatically: proxy.enablesReturnKeyAutomatically ?? false
        )
        if newTraits != traits { traits = newTraits }
        engine.capitalizationMode = newTraits.capitalization
        if hasText != proxy.hasText { hasText = proxy.hasText }
    }

    // MARK: - Keys

    func tap(_ key: Key) {
        switch key.kind {
        case .character(let character):
            if Self.wordEndingPunctuation.contains(character) { autocorrectCurrentWord() }
            activeEngine.type(character)
            // Like iOS: typing an apostrophe on the number page jumps back to letters.
            if character == "'" { page = .letters }
        case .shift:
            activeEngine.shiftTapped()
        case .delete:
            break // handled by deletePressed / deleteReleased
        case .space:
            autocorrectCurrentWord()
            activeEngine.space()
            if page != .letters { page = .letters }
        case .returnKey:
            if isTranslating {
                translateNow()
            } else {
                guard returnKeyEnabled else { return }
                autocorrectCurrentWord()
                engine.newline()
            }
        case .globe:
            controller?.advanceToNextInputMode()
        case .languageSwitch:
            switchLanguage()
        case .page(let newPage):
            page = newPage
        }
        afterEdit()
    }

    /// A long-press alternate such as é, ß, ¡ or ".nl" was picked.
    func insertAlternate(_ text: String) {
        if text.count > 1, text.hasPrefix(".") {
            // Web endings go in as they are: ".com", never ".COM".
            activeEngine.insertLiteral(text)
        } else {
            activeEngine.type(text)
        }
        afterEdit()
    }

    /// The space bar became a trackpad: lay out the text around the cursor for the floating cursor.
    func makeTrackpadSession(size: CGSize) -> TrackpadSession? {
        guard trackpadAvailable, size.width > 40 else { return nil }
        return TrackpadSession(before: proxy.documentContextBeforeInput ?? "",
                               after: proxy.documentContextAfterInput ?? "", size: size)
    }

    /// Near the edge of the text the trackpad knows: read what iOS shows around the cursor now.
    func extendTrackpadText(_ session: TrackpadSession) {
        session.extend(before: proxy.documentContextBeforeInput ?? "",
                       after: proxy.documentContextAfterInput ?? "")
    }

    /// Moves the app's cursor along with the trackpad (UTF-16 units).
    func moveCursor(by offset: Int) {
        proxy.adjustTextPosition(byCharacterOffset: offset)
    }

    /// Delete removes one character immediately, then repeats while held.
    func deletePressed() {
        activeEngine.deleteBackward()
        afterEdit()

        deleteRepeatTask?.cancel()
        deleteRepeatTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(450))
            while !Task.isCancelled {
                guard let self else { return }
                self.activeEngine.deleteBackward()
                self.feedback.deleteRepeat()
                self.afterEdit()
                try? await Task.sleep(for: .milliseconds(80))
            }
        }
    }

    func deleteReleased() {
        deleteRepeatTask?.cancel()
        deleteRepeatTask = nil
    }

    // MARK: - Suggestions (milestone 2)

    func pick(_ suggestion: Suggestion) {
        let word = TextEditing.currentWord(before: context)
        switch suggestion.kind {
        case .revert:
            guard let last = lastAutocorrection else { return }
            if word.isEmpty, context.hasSuffix(last.replacement + " ") {
                TextEditing.replaceLast(last.replacement.count + 1, with: last.original + " ", in: proxy)
            } else if word == last.replacement {
                TextEditing.replaceLast(word.count, with: last.original, in: proxy)
            }
            learn(last.original)
            lastAutocorrection = nil
            engine.noteExternalEdit()
        case .typed:
            learn(word)
            engine.space()
        case .correction, .completion:
            TextEditing.replaceLast(word.count, with: suggestion.text, in: proxy)
            engine.noteExternalEdit()
            engine.space()
        }
        afterEdit()
        buttonFeedback()
    }

    private func autocorrectCurrentWord() {
        guard !isTranslating, !TextEditing.isInsideWord(after: proxy.documentContextAfterInput) else { return }
        if expandCurrentWord() { return }
        guard languageHelpAllowed else { return }
        let word = TextEditing.currentWord(before: context)
        // You said no to expanding this shortcut; don't "correct" it either.
        guard word != declinedExpansionWord else { return }
        // Leave a word alone if the user just went back to it after an autocorrection.
        guard !word.isEmpty, lastAutocorrection?.replacement != word,
              let fixed = autocorrector.autocorrection(for: word)
        else { return }
        TextEditing.replaceLast(word.count, with: fixed, in: proxy)
        lastAutocorrection = Autocorrection(original: word, replacement: fixed)
    }

    // MARK: - Text expansions

    /// Tapped the expansion above the keys: expand right away.
    func acceptExpansion() {
        _ = expandCurrentWord()
        engine.noteExternalEdit()
        afterEdit()
        buttonFeedback()
    }

    /// Tapped ✕: keep the shortcut as typed.
    func declineExpansion() {
        declinedExpansionWord = TextEditing.currentWord(before: context)
        expansionOffer = nil
        buttonFeedback()
        updateSuggestions()
    }

    /// Replaces the shortcut before the cursor with its expansion. Undo is offered like an autocorrection.
    private func expandCurrentWord() -> Bool {
        let word = TextEditing.currentWord(before: context)
        guard word != declinedExpansionWord,
              let expansion = TextExpander.match(word, in: settings.textExpansions)
        else { return false }
        let text = TextExpander.expandedText(for: word, using: expansion)
        TextEditing.replaceLast(word.count, with: text, in: proxy)
        lastAutocorrection = Autocorrection(original: word, replacement: text)
        expansionOffer = nil
        return true
    }

    private func updatePendingExpansion() {
        let word = isTranslating ? "" : TextEditing.currentWord(before: context)
        if word != declinedExpansionWord { declinedExpansionWord = nil }
        let match = word == declinedExpansionWord ? nil : TextExpander.match(word, in: settings.textExpansions)
        let offer = match.map { ExpansionOffer(typed: word, text: TextExpander.expandedText(for: word, using: $0)) }
        if offer != expansionOffer { expansionOffer = offer }
    }

    private func updateSuggestions() {
        updatePendingExpansion()
        let word = languageHelpAllowed ? TextEditing.currentWord(before: context) : ""
        isTypingWord = !word.isEmpty
        guard languageHelpAllowed, settings.autocorrect != .off else {
            suggestions = []
            return
        }
        if word.isEmpty {
            // Right after an autocorrection, offer to undo it.
            if let last = lastAutocorrection, context.hasSuffix(last.replacement + " ") {
                suggestions = [Suggestion(text: last.original, kind: .revert)]
            } else {
                suggestions = []
            }
        } else {
            suggestions = autocorrector.suggestions(for: word, undoing: lastAutocorrection)
        }
    }

    private func learn(_ word: String) {
        guard !word.isEmpty else { return }
        learnedWordsStore.learn(word, language: settings.currentLanguage)
        autocorrector.learnedWords[settings.currentLanguage, default: []].insert(word.lowercased())
    }

    // MARK: - Grammar (milestones 3–4)

    func openIssue(_ issue: GrammarIssue) {
        aiTask?.cancel()
        explanation = .idle
        setPanel(.issue(issue))
        buttonFeedback()
    }

    func accept(_ issue: GrammarIssue, replacement: String) {
        let current = context
        if issue.range.substring(in: current) == issue.text,
           TextEditing.replace(issue.range, in: current, with: replacement, document: proxy) {
            addToLearningLog(original: issue.text, corrected: replacement, topic: issue.topic,
                             explanation: issue.englishExplanation(language: settings.currentLanguage),
                             sentence: issue.sentence)
        }
        grammarResult = nil  // the offsets have changed; check again
        engine.noteExternalEdit()
        closePanel()
    }

    func ignore(_ issue: GrammarIssue) {
        ignoredIssues.insert(issue.ignoreKey)
        closePanel()
    }

    func explainWithAI(_ issue: GrammarIssue) {
        let assistant: Assistant
        do {
            assistant = try makeAssistant()
        } catch {
            explanation = .failed(Self.message(for: error))
            return
        }
        explanation = .loading
        let language = settings.currentLanguage
        aiTask?.cancel()
        aiTask = Task { [weak self] in
            do {
                let text = try await assistant.explain(issue, language: language)
                guard !Task.isCancelled else { return }
                self?.explanation = .loaded(text)
            } catch {
                guard !Task.isCancelled else { return }
                self?.explanation = .failed(Self.message(for: error))
            }
        }
    }

    private func scheduleGrammarCheck() {
        grammarTask?.cancel()
        guard grammarAllowed else {
            grammarResult = nil
            grammarStatus = .idle
            return
        }
        let language = settings.currentLanguage
        let level = settings.grammarLevel
        let languageTool = hasFullAccess ? LanguageToolClient(urlString: settings.languageToolURL) : nil
        let checker = grammarChecker
        grammarTask = Task { [weak self] in
            // Wait for a pause in typing; the public LanguageTool server allows about 20 checks a minute.
            try? await Task.sleep(for: .milliseconds(1200))
            guard let self, !Task.isCancelled else { return }
            let text = self.context
            guard text.contains(where: \.isLetter) else { return }
            if self.grammarResult?.text == text, self.grammarResult?.language == language { return }

            if languageTool != nil { self.grammarStatus = .checking }
            let result = await checker.check(text, language: language, level: level, languageTool: languageTool)
            guard !Task.isCancelled else { return }
            self.grammarResult = result
            self.grammarStatus = result.warning.map(GrammarStatus.warning) ?? .idle
            self.refreshLiveIssues()
        }
    }

    private func refreshLiveIssues() {
        guard grammarAllowed, let result = grammarResult, result.language == settings.currentLanguage else {
            if !issues.isEmpty { issues = [] }
            return
        }
        let live = result.liveIssues(in: context, ignoring: ignoredIssues)
        if live != issues { issues = live }
    }

    // MARK: - Tools: Is this correct? / Improve (milestone 4b)

    func openTools() {
        setPanel(panel == .tools ? .none : .tools)
        buttonFeedback()
    }

    func startReview(_ mode: ReviewRequest.Mode) {
        aiTask?.cancel()
        guard let span = TextEditing.currentSentence(before: context) else {
            setPanel(.review(ReviewRequest(mode: mode, span: nil)))
            review = .failed("Type a sentence first, then try again.")
            return
        }
        setPanel(.review(ReviewRequest(mode: mode, span: span)))

        let assistant: Assistant
        do {
            assistant = try makeAssistant()
        } catch {
            review = .failed(Self.message(for: error))
            return
        }
        review = .loading
        let language = settings.currentLanguage
        let level = settings.grammarLevel
        aiTask = Task { [weak self] in
            do {
                let result = mode == .check
                    ? try await assistant.check(span.text, language: language, level: level)
                    : try await assistant.improve(span.text, language: language)
                guard !Task.isCancelled else { return }
                self?.review = .loaded(result)
            } catch {
                guard !Task.isCancelled else { return }
                self?.review = .failed(Self.message(for: error))
            }
        }
    }

    /// Replaces the reviewed sentence with the AI's version.
    func useRevision(_ result: SentenceReview, for request: ReviewRequest) {
        let current = context
        guard let span = request.span, span.range.substring(in: current) == span.text else {
            // The text changed while the AI was thinking; don't overwrite the wrong thing.
            review = .failed("The text changed in the meantime. Close this and try again.")
            return
        }
        TextEditing.replace(span.range, in: current, with: result.revised, document: proxy)
        for change in result.changes where !change.optional {
            addToLearningLog(original: change.original, corrected: change.replacement, topic: change.grammarTopic,
                             explanation: change.explanation, sentence: span.text)
        }
        grammarResult = nil
        engine.noteExternalEdit()
        closePanel()
    }

    // MARK: - Translator (milestone 5)

    func openTranslator() {
        buffer.text = ""
        translatorInput = ""
        translation = .idle
        translationSource = nil
        page = .letters
        setPanel(.translator)
        bufferEngine.updateAutoCapitalization()
        syncShift()
    }

    /// Puts the sentence from the text field into the translator, so Insert replaces it.
    func translateFieldText() {
        guard let span = TextEditing.currentSentence(before: context) else { return }
        translationSource = span
        buffer.text = span.text
        translatorInput = span.text
        bufferEngine.noteExternalEdit()
        syncShift()
        translateNow()
    }

    /// Cycles the source or target language, skipping the one on the other side.
    func cycleTranslationLanguage(source: Bool) {
        var latest = store.load()
        let other = source ? latest.translateTo : latest.translateFrom
        let current = source ? latest.translateFrom : latest.translateTo
        let all = KeyboardLanguage.allCases
        var index = all.firstIndex(of: current) ?? 0
        repeat { index = (index + 1) % all.count } while all[index] == other
        if source { latest.translateFrom = all[index] } else { latest.translateTo = all[index] }
        saveTranslatorLanguages(latest)
    }

    func swapTranslationLanguages() {
        var latest = store.load()
        (latest.translateFrom, latest.translateTo) = (latest.translateTo, latest.translateFrom)
        if case .loaded(let result) = translation {
            // Swapping after a translation: continue from the translated text.
            buffer.text = result.translation
            translatorInput = result.translation
            translationSource = nil
        }
        saveTranslatorLanguages(latest)
    }

    func insertTranslation() {
        guard case .loaded(let result) = translation else { return }
        let current = context
        if let source = translationSource, source.range.substring(in: current) == source.text {
            TextEditing.replace(source.range, in: current, with: result.translation, document: proxy)
        } else {
            let needsSpace = current.last.map { !$0.isWhitespace } ?? false
            proxy.insertText((needsSpace ? " " : "") + result.translation)
        }
        engine.noteExternalEdit()
        closePanel()
    }

    private func saveTranslatorLanguages(_ latest: TaalhulpSettings) {
        store.save(latest)
        settings = latest
        translateNow()
    }

    private func scheduleTranslation() {
        translateTask?.cancel()
        guard !buffer.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            translation = .idle
            return
        }
        translateTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(1200))
            guard !Task.isCancelled else { return }
            await self?.runTranslation()
        }
    }

    private func translateNow() {
        translateTask?.cancel()
        translateTask = Task { [weak self] in await self?.runTranslation() }
    }

    private func runTranslation() async {
        let text = buffer.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            translation = .idle
            return
        }
        let assistant: Assistant
        do {
            assistant = try makeAssistant()
        } catch {
            translation = .failed(Self.message(for: error))
            return
        }
        translation = .loading
        do {
            let result = try await assistant.translate(text, from: settings.translateFrom, to: settings.translateTo)
            guard !Task.isCancelled,
                  buffer.text.trimmingCharacters(in: .whitespacesAndNewlines) == text
            else { return }
            translation = .loaded(result)
        } catch {
            guard !Task.isCancelled else { return }
            translation = .failed(Self.message(for: error))
        }
    }

    // MARK: - Panels

    func closePanel() {
        aiTask?.cancel()
        translateTask?.cancel()
        explanation = .idle
        review = .idle
        setPanel(.none)
        engine.updateAutoCapitalization()
        syncShift()
        textChanged()
    }

    private func setPanel(_ newPanel: Panel) {
        guard newPanel != panel else { return }
        let heightChanges = (newPanel == .translator) != (panel == .translator)
        panel = newPanel
        if heightChanges { onPanelChange?(newPanel) }
    }

    // MARK: - Helpers

    /// Tells the app which build is running and which touch map is in use (Settings → Touch map),
    /// and logs it for Xcode's console.
    private func reportToApp(trainedTaps: Int) {
        let report = KeyboardReport(build: BuildInfo.executableDate, touchModel: settings.touchModel,
                                    trainedTaps: trainedTaps)
        store.saveKeyboardReport(report)
        let build = report.build.map { $0.formatted(date: .abbreviated, time: .standard) } ?? "unknown"
        Self.log.notice("Keyboard build \(build, privacy: .public), touch map \(report.touchModel.rawValue, privacy: .public), \(trainedTaps) trained taps, Full Access \(self.hasFullAccess)")
    }

    /// After every key: refresh whatever depends on the text. Shift updates at once; suggestions
    /// and grammar (spell checking takes a few milliseconds) wait until the key press is on screen.
    private func afterEdit() {
        syncShift()
        if isTranslating {
            translatorInput = buffer.text
            scheduleTranslation()
        } else {
            if let proxy = controller?.textDocumentProxy, hasText != proxy.hasText { hasText = proxy.hasText }
            scheduleTextAnalysis()
        }
    }

    private func scheduleTextAnalysis() {
        guard !textAnalysisPending else { return }
        textAnalysisPending = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.textAnalysisPending = false
            if !self.isTranslating { self.textChanged() }
        }
    }

    private func textChanged() {
        if let proxy = controller?.textDocumentProxy, hasText != proxy.hasText { hasText = proxy.hasText }
        updateSuggestions()
        refreshLiveIssues()
        scheduleGrammarCheck()
    }

    private func switchLanguage() {
        if isTranslating {
            cycleTranslationLanguage(source: true)
            return
        }
        // Reload first so we don't overwrite changes made in the app meanwhile.
        var latest = store.load()
        latest.currentLanguage = settings.currentLanguage
        latest.currentLanguage = latest.nextLanguage()
        store.save(latest)
        settings = latest
        autocorrector.language = latest.currentLanguage
        lastAutocorrection = nil
        grammarResult = nil
    }

    private func makeAssistant() throws -> Assistant {
        Assistant(client: try AIClientFactory.make(settings, hasFullAccess: hasFullAccess))
    }

    private func addToLearningLog(original: String, corrected: String, topic: GrammarTopic,
                                  explanation: String, sentence: String) {
        guard settings.keepLearningLog, original != corrected else { return }
        learningLog.add(LearningEntry(language: settings.currentLanguage, topic: topic, original: original,
                                      corrected: corrected, explanation: explanation, sentence: sentence))
    }

    private func syncShift() {
        let current = activeEngine.shift
        if shift != current { shift = current }
    }

    /// Taps on the suggestion bar, chips and panels (keys get theirs from `KeyTouchHandler`).
    private func buttonFeedback() {
        feedback.buttonTap()
    }

    private static func message(for error: Error) -> String {
        if let error = error as? LocalizedError, let text = error.errorDescription { return text }
        if let error = error as? URLError {
            return error.code == .notConnectedToInternet ? "No internet connection." : "Network error. Try again."
        }
        return "Something went wrong. Try again."
    }

    // MARK: - UIKit → KeyboardCore

    private static func fieldKind(_ type: UIKeyboardType) -> FieldKind {
        switch type {
        case .emailAddress: .email
        case .URL: .url
        case .webSearch: .webSearch
        default: .text
        }
    }

    private static func returnKeyStyle(_ type: UIReturnKeyType) -> ReturnKeyStyle {
        switch type {
        case .go: .go
        case .google, .yahoo, .search: .search
        case .join: .join
        case .next: .next
        case .route: .route
        case .send: .send
        case .done: .done
        case .emergencyCall: .emergencyCall
        case .continue: .continue
        case .default: .default
        @unknown default: .default
        }
    }

    private static func capitalization(_ type: UITextAutocapitalizationType) -> AutocapitalizationMode {
        switch type {
        case .none: .none
        case .words: .words
        case .sentences: .sentences
        case .allCharacters: .allCharacters
        @unknown default: .sentences
        }
    }
}
