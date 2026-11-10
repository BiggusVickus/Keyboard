import XCTest
@testable import KeyboardCore

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
    /// Like WhatsApp: the text before the cursor only reaches back to the start of the current
    /// sentence, and is empty right at a sentence start.
    let sentenceLimited: Bool

    init(_ text: String, cursorFromEnd: Int = 0, window: Int = 40, lag: Int = 0, sentenceLimited: Bool = false) {
        buffer = TextBuffer(text)
        self.window = window
        self.lag = lag
        self.sentenceLimited = sentenceLimited
        buffer.adjustTextPosition(byCharacterOffset: -cursorFromEnd)
    }

    var documentContextBeforeInput: String? {
        if let staleBefore { return staleBefore }
        var before = String(buffer.beforeCursor.suffix(window))
        if sentenceLimited, let start = before.range(of: ". ", options: .backwards) {
            before = String(before[start.upperBound...])
        }
        return before
    }
    var documentContextAfterInput: String? { staleAfter ?? String(buffer.afterCursor.prefix(window)) }
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
        buffer.adjustTextPosition(byCharacterOffset: offset)
    }

    func settle() {
        guard settlesLeft > 0 else { return }
        settlesLeft -= 1
        if settlesLeft == 0 { staleBefore = nil; staleAfter = nil }
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
