import XCTest
@testable import KeyboardCore

/// Where sentences start, in characters: 0, and after every . ! ? plus the spaces after it.
private func startsOfSentences(in text: String) -> [Int] {
    let chars = Array(text)
    var starts = [0]
    var i = 0
    while i < chars.count {
        if ".!?".contains(chars[i]) {
            var j = i + 1
            while j < chars.count, chars[j].isWhitespace { j += 1 }
            if j > i + 1 { starts.append(j) }
            i = j
        } else {
            i += 1
        }
    }
    return starts
}

/// Behaves like iOS's text proxy as a real reading log showed it (18 Nov 2026). Right after the cursor
/// moves, iOS shows its own guess: what it showed before, shifted along by the move, as far as that
/// reaches (so nothing on a side it ran out of). The app's own view for each move arrives `lag`
/// `settle()`s later, in order. Like that app, it shows from the start of the previous sentence up to
/// the cursor, and from the cursor to the end of its sentence, at most `cap` characters each.
/// `whatsApp`: only the cursor's own sentence, and one character back from the very start jumps to the
/// end of the first sentence.
private final class GuessingDocument: TextDocument {
    let buffer: TextBuffer
    let cap: Int
    let lag: Int
    let whatsApp: Bool
    private var shown: (before: String, after: String) = ("", "")
    private var answers: [(due: Int, before: String, after: String)] = []
    private var clock = 0

    init(_ text: String, cursorFromEnd: Int = 0, cap: Int = 300, lag: Int = 2, whatsApp: Bool = false) {
        buffer = TextBuffer(text)
        self.cap = cap
        self.lag = lag
        self.whatsApp = whatsApp
        buffer.adjustTextPosition(byCharacterOffset: -cursorFromEnd)
        shown = appView()
    }

    /// What the app shows around the cursor.
    private func appView() -> (before: String, after: String) {
        let cursor = buffer.beforeCursor.count
        let starts = startsOfSentences(in: buffer.text)
        let current = starts.lastIndex { $0 <= cursor } ?? 0
        let from = starts[whatsApp ? current : max(current - 1, 0)]
        let to = current + 1 < starts.count ? starts[current + 1] : buffer.text.count
        return (String(buffer.beforeCursor.dropFirst(from).suffix(cap)),
                String(buffer.afterCursor.prefix(to - cursor).prefix(cap)))
    }

    var documentContextBeforeInput: String? { shown.before }
    var documentContextAfterInput: String? { shown.after }

    func adjustTextPosition(byCharacterOffset offset: Int) {
        let guess = TextBuffer(shown.before + shown.after)
        guess.adjustTextPosition(byCharacterOffset: -shown.after.utf16.count)
        guess.adjustTextPosition(byCharacterOffset: offset)
        shown = (guess.beforeCursor, guess.afterCursor)

        let starts = startsOfSentences(in: buffer.text)
        if whatsApp, offset < 0, buffer.beforeCursor.isEmpty, starts.count > 1 {
            var firstSentence = String(buffer.text.prefix(starts[1]))
            while firstSentence.last?.isWhitespace == true { firstSentence.removeLast() }
            buffer.adjustTextPosition(byCharacterOffset: firstSentence.utf16.count)
        } else {
            buffer.adjustTextPosition(byCharacterOffset: offset)
        }
        let view = appView()
        answers.append((clock + lag, view.before, view.after))
    }

    func settle() {
        clock += 1
        while let answer = answers.first, answer.due <= clock {
            shown = (answer.before, answer.after)
            answers.removeFirst()
        }
    }

    func insertText(_ text: String) {
        buffer.insertText(text)
        answers = []
        shown = appView()
    }

    func deleteBackward() {
        buffer.deleteBackward()
        answers = []
        shown = appView()
    }
}

/// Behaves like iOS's text proxy: shows only `window` characters on each side of the cursor, and
/// after the cursor moves it keeps showing the old window until `settle()` has run `lag` times.
private final class WindowedDocument: TextDocument {
    let buffer: TextBuffer
    let window: Int
    let lag: Int
    private var staleBefore: String?
    private var staleAfter: String?
    private var settlesLeft = 0
    var selection: String?
    /// Like WhatsApp (seen in a real reading log): before and after the cursor only show the
    /// sentence the cursor is in. A sentence includes the spaces after its full stop, and a cursor
    /// right at a sentence start belongs to the next sentence, so "before" is empty there.
    let sentenceLimited: Bool
    /// Also like WhatsApp: moving one character back from the very start of the text puts the
    /// cursor at the end of the first sentence instead of doing nothing.
    let jumpsAtStart: Bool

    init(_ text: String, cursorFromEnd: Int = 0, window: Int = 40, lag: Int = 0,
         sentenceLimited: Bool = false, jumpsAtStart: Bool = false) {
        buffer = TextBuffer(text)
        self.window = window
        self.lag = lag
        self.sentenceLimited = sentenceLimited
        self.jumpsAtStart = jumpsAtStart
        buffer.adjustTextPosition(byCharacterOffset: -cursorFromEnd)
    }

    private var sentenceStarts: [Int] { startsOfSentences(in: buffer.text) }

    /// The sentence around the cursor, in characters.
    private var sentence: (start: Int, end: Int) {
        let cursor = buffer.beforeCursor.count
        let starts = sentenceStarts
        return (starts.last { $0 <= cursor } ?? 0, starts.first { $0 > cursor } ?? buffer.text.count)
    }

    var documentContextBeforeInput: String? {
        if let staleBefore { return staleBefore }
        guard sentenceLimited else { return String(buffer.beforeCursor.suffix(window)) }
        return String(buffer.beforeCursor.dropFirst(sentence.start).suffix(window))
    }
    var documentContextAfterInput: String? {
        if let staleAfter { return staleAfter }
        guard sentenceLimited else { return String(buffer.afterCursor.prefix(window)) }
        let cursor = buffer.beforeCursor.count
        return String(buffer.afterCursor.prefix(sentence.end - cursor).prefix(window))
    }
    var selectedText: String? { selection }

    func insertText(_ text: String) {
        if selection != nil { selection = nil }   // typing replaces the selection (handled by the test)
        buffer.insertText(text)
    }
    func deleteBackward() { buffer.deleteBackward() }

    func adjustTextPosition(byCharacterOffset offset: Int) {
        if lag > 0, staleBefore == nil {
            staleBefore = documentContextBeforeInput
            staleAfter = documentContextAfterInput
            settlesLeft = lag
        }
        if jumpsAtStart, offset < 0, buffer.beforeCursor.isEmpty, sentenceStarts.count > 1 {
            // To just before the space after the first sentence's full stop.
            let firstEnd = Array(buffer.text)[..<sentenceStarts[1]].lastIndex { !$0.isWhitespace }.map { $0 + 1 } ?? 0
            let target = String(buffer.text.prefix(firstEnd))
            buffer.adjustTextPosition(byCharacterOffset: target.utf16.count)
            return
        }
        buffer.adjustTextPosition(byCharacterOffset: offset)
    }

    func settle() {
        guard settlesLeft > 0 else { return }
        settlesLeft -= 1
        if settlesLeft == 0 { staleBefore = nil; staleAfter = nil }
    }
}

/// The whole field is selected, and the app passes on only part of the selection. Moving the cursor
/// ends the selection (iOS puts it at the end of the field).
private final class SelectAllDocument: TextDocument {
    let buffer: TextBuffer
    private var reportedSelection: String?

    init(_ text: String, reportedSelection: String) {
        buffer = TextBuffer(text)
        self.reportedSelection = reportedSelection
    }

    var selectedText: String? { reportedSelection }
    var documentContextBeforeInput: String? { reportedSelection == nil ? buffer.documentContextBeforeInput : "" }
    var documentContextAfterInput: String? { reportedSelection == nil ? buffer.documentContextAfterInput : "" }
    func insertText(_ text: String) { buffer.insertText(text) }
    func deleteBackward() { buffer.deleteBackward() }
    func adjustTextPosition(byCharacterOffset offset: Int) {
        if reportedSelection != nil {
            reportedSelection = nil   // cursor at the end of the field (TextBuffer starts there)
        } else {
            buffer.adjustTextPosition(byCharacterOffset: offset)
        }
    }
}

@MainActor
final class FullTextTests: XCTestCase {
    private let long = (1...30).map { "Dit is zin nummer \($0), en hij is niet zo lang." }.joined(separator: " ")
        + "\nEen nieuwe regel met een emoji 🇳🇱 erin."

    func testReadsTheWholeTextFromTheMiddleThroughSmallWindows() async {
        let document = WindowedDocument(long, cursorFromEnd: 700)
        let text = await FullText.read(document) {}
        XCTAssertEqual(text, long)
        XCTAssertEqual(document.buffer.afterCursor, "", "the cursor ends at the end of the text")
    }

    func testReadsPastSentenceStartsLikeWhatsApp() async {
        // 60 words in a few sentences, cursor at the end: the whole message, not just the last sentence.
        let message = "Hoi! Ik wilde even laten weten dat ik morgen wat later ben, want de trein rijdt niet. "
            + "Kunnen we om half acht afspreken in plaats van zeven uur? Dan haal ik onderweg nog wat te eten. "
            + "Laat maar weten of dat goed is voor jou en de anderen, dan stuur ik het adres nog even door."
        let document = WindowedDocument(message, window: 200, sentenceLimited: true)
        let text = await FullText.read(document) {}
        XCTAssertEqual(text, message)
        XCTAssertEqual(document.buffer.afterCursor, "")
    }

    func testWhatsAppJumpAtTheStartIsNotMoreText() async {
        // Replays the real reading log: WhatsApp shows one sentence at a time, and one character
        // back from the very start lands at the end of the first sentence. The reader must stop
        // there, not read the first sentence again and again.
        let message = "Hoi mijn naam is Victor. Ik ben 23 jaar oud. "
            + "Ik woon in Nederland en ik speel hockey, en zaterdag hebben we een wedstrijd. "
            + "Hoi allemaal, kom kijken naar ons op zaterdag bij een wedstrijd. "
        for lag in [0, 2] {
            let document = WindowedDocument(message, window: 200, lag: lag, sentenceLimited: true, jumpsAtStart: true)
            var log: [String] = []
            let text = await FullText.read(document, log: { log.append($0) }) { document.settle() }
            XCTAssertEqual(text, message, "lag \(lag):\n" + log.joined(separator: "\n"))
            XCTAssertEqual(document.buffer.afterCursor, "", "the cursor ends at the end of the text")
            XCTAssertLessThan(log.count, 30, "no looping:\n" + log.joined(separator: "\n"))
        }
    }

    /// The text from the reading log of 18 Nov 2026, where only the last two sentences were read.
    private let refereeing = "Afgelopen a a a a a a a a a a a a zaterdag stond ik al vroeg op, want ik had twee wedstrijden ingepland als scheidsrechter bij de club. "
        + "Het was koud en een beetje mistig toen ik naar het sportpark fietste, maar met een warme jas en een thermoskan koffie viel het gelukkig mee. "
        + "De eerste wedstrijd was van de MO12-4, en die meiden speelden met ontzettend veel enthousiasme, ook al was het veld nog nat van de regen van de nacht ervoor. "
        + "Daarna had ik een korte pauze, dus ik ging even naar de kantine om iets te eten en met een paar ouders te praten over het nieuwe seizoen en de trainingen. "
        + "De tweede wedstrijd, van de MO14-4, was een stuk spannender, omdat beide teams bovenaan in de competitie staan en duidelijk wilden winnen. "
        + "Ik moest goed opletten, vooral bij een paar lastige situaties rond de zestien, maar de spelers bleven sportief en accepteerden mijn beslissingen zonder al te veel discussie. "
        + "Toen ik aan het eind van de middag weer naar huis fietste, was ik moe maar ook voldaan, en ik besefte dat ik dit soort vrijwilligerswerk eigenlijk steeds leuker begin te vinden, niet alleen vanwege het voetbal, maar ook omdat ik zo meer mensen uit de buurt leer kennen en mijn Nederlands elke week een beetje beter wordt. "

    func testReadsPastTheEndOfIOSsGuess() async {
        // Replays the real reading log: after stepping back by all it showed, iOS's guess shows nothing
        // before the cursor, and the app's view (a different length) arrives later. Before, the reader
        // took that for the start and the end of the text, and read only the last two sentences.
        for lag in [1, 2, 5] {
            for cursorFromEnd in [0, 150, 700, refereeing.count] {
                let document = GuessingDocument(refereeing, cursorFromEnd: cursorFromEnd, lag: lag)
                var log: [String] = []
                let text = await FullText.read(document, log: { log.append($0) }) { document.settle() }
                let context = "lag \(lag), cursor \(cursorFromEnd) from the end:\n" + log.joined(separator: "\n")
                XCTAssertEqual(text, refereeing, context)
                XCTAssertEqual(document.buffer.afterCursor, "", "the cursor ends at the end of the text. " + context)
            }
        }
    }

    func testTheGuessingDocumentShowsWhatTheRealLogShowed() async {
        // The first steps of the real log, so the stand-in for iOS stays honest.
        let document = GuessingDocument(refereeing)
        var log: [String] = []
        _ = await FullText.read(document, log: { log.append($0) }) { document.settle() }
        let joined = log.joined(separator: "\n")
        XCTAssertEqual(log.first, "start: before [300] \"an de middag wee…je beter wordt. \", after [0] \"\"", joined)
        XCTAssertTrue(log.contains { $0.hasPrefix("back 300, waited 0: before [0] \"\", after [300]") }, joined)
        XCTAssertTrue(log.contains { $0.contains("before [195] \"Ik moest goed op…ik aan het eind \"") }, joined)
        XCTAssertTrue(log.contains { $0.hasPrefix("back 195, waited 0: before [0] \"\", after [495]") }, joined)
    }

    func testReadsWhatsAppThroughIOSsGuess() async {
        let messages = [
            "Hoi mijn naam is Victor. Ik ben 23 jaar oud. Ik woon in Nederland en ik speel hockey. ",
            "Hoi! Kunnen we om half acht afspreken in plaats van zeven uur? Dan haal ik onderweg nog wat te eten.",
            "Haha. Haha. Ok.",      // repeats itself, but that's no jump to the start
            "Prima, tot morgen. ",  // one sentence: the jump lands at the end
            refereeing,
        ]
        for message in messages {
            for lag in [1, 3] {
                for cursorFromEnd in [0, 3] {
                    let document = GuessingDocument(message, cursorFromEnd: cursorFromEnd, cap: 200, lag: lag, whatsApp: true)
                    var log: [String] = []
                    let text = await FullText.read(document, log: { log.append($0) }) { document.settle() }
                    let context = "\(message.prefix(20))…, lag \(lag), cursor \(cursorFromEnd) from the end:\n" + log.joined(separator: "\n")
                    XCTAssertEqual(text, message, context)
                    XCTAssertEqual(document.buffer.afterCursor, "", context)
                }
            }
        }
    }

    func testReplacesAfterReadingThroughIOSsGuess() async throws {
        let document = GuessingDocument(refereeing, cursorFromEnd: 400)
        let read = await FullText.read(document) { document.settle() }
        let text = try XCTUnwrap(read)
        XCTAssertTrue(FullText.replace(text, with: "Zaterdag was ik scheidsrechter.", in: document))
        XCTAssertEqual(document.buffer.text, "Zaterdag was ik scheidsrechter.")
    }

    func testMessageEndingInASpaceAfterAFullStop() async {
        // Right after ". " WhatsApp shows nothing before the cursor at all.
        let message = "Prima, tot morgen. Neem je de sleutel mee? Ik ben er om acht uur. "
        let document = WindowedDocument(message, cursorFromEnd: 30, sentenceLimited: true)
        let text = await FullText.read(document) {}
        XCTAssertEqual(text, message)
        XCTAssertEqual(document.buffer.afterCursor, "")
    }

    func testReplacesAWhatsAppMessageEndingInASpace() async throws {
        let message = "Prima, tot morgen. Ik ben er om acht uur. "
        let document = WindowedDocument(message, sentenceLimited: true)
        let read = await FullText.read(document) {}
        let text = try XCTUnwrap(read)
        XCTAssertTrue(FullText.replace(text, with: "Prima, tot morgen! Ik ben er om acht uur.", in: document))
        XCTAssertEqual(document.buffer.text, "Prima, tot morgen! Ik ben er om acht uur.")
    }

    func testEmptyFieldReadsAsEmpty() async {
        let text = await FullText.read(WindowedDocument("", sentenceLimited: true)) {}
        XCTAssertEqual(text, "")
    }

    func testSentenceLimitedAndSlow() async {
        let document = WindowedDocument(long, cursorFromEnd: 200, lag: 2, sentenceLimited: true)
        let text = await FullText.read(document) { document.settle() }
        XCTAssertEqual(text, long)
    }

    func testWaitsForASlowTextField() async {
        let document = WindowedDocument(long, cursorFromEnd: 300, lag: 3)
        let text = await FullText.read(document) { document.settle() }
        XCTAssertEqual(text, long)
    }

    func testGivesUpWhenTheFieldNeverCatchesUp() async {
        let document = WindowedDocument(long, cursorFromEnd: 300, lag: 1000)
        let text = await FullText.read(document) { document.settle() }
        XCTAssertNil(text)
    }

    func testGivesUpOnVeryLongText() async {
        let document = WindowedDocument(long)
        let text = await FullText.read(document, maxLength: 200) {}
        XCTAssertNil(text)
        XCTAssertEqual(document.buffer.afterCursor, "", "the cursor is put back at the end")
    }

    func testReplacesTheWholeText() async throws {
        let document = WindowedDocument(long, cursorFromEnd: 100)
        let read = await FullText.read(document) {}
        let text = try XCTUnwrap(read)
        XCTAssertTrue(FullText.replace(text, with: "Helemaal nieuw.", in: document))
        XCTAssertEqual(document.buffer.text, "Helemaal nieuw.")
    }

    func testDoesNotReplaceWhenTheTextChanged() async throws {
        let document = WindowedDocument(long)
        let read = await FullText.read(document) {}
        let text = try XCTUnwrap(read)
        document.insertText(" Nog iets.")
        XCTAssertFalse(FullText.replace(text, with: "Weg.", in: document))
        XCTAssertTrue(document.buffer.text.hasSuffix("Nog iets."))
    }

    func testPartialSelectionIsUsedAsIs() async {
        let document = WindowedDocument("Ik heb een fiets gekoopt. Hij is rood.", cursorFromEnd: 13)
        document.selection = "gekoopt"
        let target = await FullText.readTarget(document) {}
        XCTAssertEqual(target, .selection("gekoopt"))
    }

    func testWholeFieldSelectedIsReadInFull() async {
        // Everything selected: nothing before or after the selection. Don't trust the selection text
        // (apps may pass on only part of it): read the field.
        let message = "Hallo mijn naam is Victor. Ik heb twee voeten. Er zijn 5 tenen op elke voet. Ik spel hockey. Ik ben niet lang."
        let document = SelectAllDocument(message, reportedSelection: "Hallo mijn naam is Victor. Ik ben niet lang.")
        var log: [String] = []
        let target = await FullText.readTarget(document, log: { log.append($0) }) {}
        XCTAssertEqual(target, .wholeText(message))
        XCTAssertTrue(log.contains { $0.contains("whole field was selected") }, log.joined(separator: "\n"))
    }

    func testReadingLogDescribesEachStep() async {
        var log: [String] = []
        let document = WindowedDocument(long, cursorFromEnd: 100, sentenceLimited: true)
        _ = await FullText.read(document, log: { log.append($0) }) {}
        XCTAssertTrue(log.first?.hasPrefix("start: before [") == true, log.joined(separator: "\n"))
        XCTAssertEqual(log.last, "read \(long.count) characters")
    }

    func testReplacesOnlyTheSameSelection() {
        let document = WindowedDocument("Ik heb een fiets gekoopt.")
        document.selection = "gekoopt"
        XCTAssertFalse(FullText.replaceSelection("iets anders", with: "x", in: document))
        XCTAssertTrue(FullText.replaceSelection("gekoopt", with: "gekocht", in: document))
    }

    func testSentenceAroundAChange() {
        let text = "Hallo. Gisteren ik ben naar huis gegaan. Daarna sliep ik."
        XCTAssertEqual(FullText.sentence(containing: "ik ben", in: text), "Gisteren ik ben naar huis gegaan.")
    }

    func testLongTextsGetMoreRoomInTheAnswer() {
        XCTAssertEqual(Assistant.reviewMaxTokens(for: "Kort."), 4002)
        XCTAssertEqual(Assistant.reviewMaxTokens(for: String(repeating: "a", count: 100_000)), 16_000)
    }
}
