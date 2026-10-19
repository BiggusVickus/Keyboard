import XCTest
@testable import KeyboardCore

final class TextEditingTests: XCTestCase {
    func testCurrentWord() {
        XCTAssertEqual(TextEditing.currentWord(before: "Ik ben thu"), "thu")
        XCTAssertEqual(TextEditing.currentWord(before: "Ik ben "), "")
        XCTAssertEqual(TextEditing.currentWord(before: ""), "")
        XCTAssertEqual(TextEditing.currentWord(before: "zo'n"), "zo'n")
        XCTAssertEqual(TextEditing.currentWord(before: "mijn e-mail"), "e-mail")
        XCTAssertEqual(TextEditing.currentWord(before: "auto'"), "", "a trailing apostrophe isn't part of a word")
        XCTAssertEqual(TextEditing.currentWord(before: "(hallo"), "hallo")
    }

    func testInsideWord() {
        XCTAssertTrue(TextEditing.isInsideWord(after: "is"))
        XCTAssertFalse(TextEditing.isInsideWord(after: " is"))
        XCTAssertFalse(TextEditing.isInsideWord(after: nil))
    }

    func testCurrentSentence() {
        let span = TextEditing.currentSentence(before: "Hallo. Ik ben thuis. ")
        XCTAssertEqual(span?.text, "Ik ben thuis.")
        XCTAssertEqual(span?.range, UTF16Range(location: 7, length: 13))

        XCTAssertEqual(TextEditing.currentSentence(before: "Eerste regel\nTweede zin")?.text, "Tweede zin")
        XCTAssertEqual(TextEditing.currentSentence(before: "Wat? Echt")?.text, "Echt")
        XCTAssertNil(TextEditing.currentSentence(before: "   "))
    }

    func testReplaceInMiddleKeepsCursorAtEnd() {
        let doc = TextBuffer("Het auto is rood")
        let context = doc.text
        let ok = TextEditing.replace(UTF16Range(location: 0, length: 3), in: context, with: "De", document: doc)
        XCTAssertTrue(ok)
        XCTAssertEqual(doc.text, "De auto is rood")
        XCTAssertEqual(doc.afterCursor, "", "cursor goes back to the end")
    }

    func testReplaceWithAccentsAndEmoji() {
        let doc = TextBuffer("Één 👍 fuot")
        let context = doc.text
        let range = UTF16Range(location: (context.utf16.count - 4), length: 4)
        XCTAssertEqual(range.substring(in: context), "fuot")
        TextEditing.replace(range, in: context, with: "fout", document: doc)
        XCTAssertEqual(doc.text, "Één 👍 fout")
    }

    func testReplaceRejectsBadRange() {
        let doc = TextBuffer("kort")
        XCTAssertFalse(TextEditing.replace(UTF16Range(location: 2, length: 10), in: doc.text, with: "x", document: doc))
        XCTAssertEqual(doc.text, "kort")
    }

    func testRangeThatSplitsEmojiIsRejected() {
        XCTAssertNil(UTF16Range(location: 1, length: 1).substring(in: "👍a"))
    }

    func testMatchCase() {
        XCTAssertEqual(TextEditing.matchCase("the", to: "Teh"), "The")
        XCTAssertEqual(TextEditing.matchCase("the", to: "TEH"), "THE")
        XCTAssertEqual(TextEditing.matchCase("Haus", to: "hause"), "Haus", "never lowercases")
        XCTAssertEqual(TextEditing.matchCase("I", to: "i"), "I")
    }

    func testBufferCursorMoves() {
        let buffer = TextBuffer("abc")
        buffer.adjustTextPosition(byCharacterOffset: -2)
        buffer.insertText("X")
        XCTAssertEqual(buffer.text, "aXbc")
        buffer.adjustTextPosition(byCharacterOffset: 10)
        XCTAssertEqual(buffer.afterCursor, "")
    }
}
