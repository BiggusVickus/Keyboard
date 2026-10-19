import XCTest
@testable import KeyboardCore

/// A pretend text field for tests.
typealias FakeDocument = TextBuffer

final class TypingEngineTests: XCTestCase {
    func testCapitalizesFirstLetterThenLowercase() {
        let doc = FakeDocument()
        let engine = TypingEngine(document: doc)
        engine.updateAutoCapitalization()

        engine.type("i")
        engine.type("k")
        XCTAssertEqual(doc.text, "Ik")
    }

    func testCapitalizesAfterSentenceEnd() {
        let doc = FakeDocument()
        doc.text = "Hallo."
        let engine = TypingEngine(document: doc)
        engine.space()
        engine.type("h")
        XCTAssertEqual(doc.text, "Hallo. H")
    }

    func testNoCapitalizationMidSentence() {
        let doc = FakeDocument()
        doc.text = "Ik heb"
        let engine = TypingEngine(document: doc)
        engine.space()
        engine.type("h")
        XCTAssertEqual(doc.text, "Ik heb h")
    }

    func testDoubleSpaceInsertsPeriod() {
        let doc = FakeDocument()
        doc.text = "Dank je"
        let engine = TypingEngine(document: doc)
        engine.space()
        engine.space()
        XCTAssertEqual(doc.text, "Dank je. ")
        XCTAssertEqual(engine.shift, .once)
    }

    func testShiftDoubleTapIsCapsLock() {
        var time = Date(timeIntervalSince1970: 0)
        let doc = FakeDocument()
        doc.text = "a "
        let engine = TypingEngine(document: doc, now: { time })
        engine.updateAutoCapitalization()
        XCTAssertEqual(engine.shift, .off)

        engine.shiftTapped()
        XCTAssertEqual(engine.shift, .once)
        time += 0.2
        engine.shiftTapped()
        XCTAssertEqual(engine.shift, .capsLock)

        engine.type("a")
        engine.type("b")
        XCTAssertEqual(doc.text, "a AB")
    }

    func testSlowSecondShiftTapTurnsShiftOff() {
        var time = Date(timeIntervalSince1970: 0)
        let doc = FakeDocument()
        doc.text = "a "
        let engine = TypingEngine(document: doc, now: { time })
        engine.shiftTapped()
        time += 1
        engine.shiftTapped()
        XCTAssertEqual(engine.shift, .off)
    }

    func testAutoCapitalizeCanBeTurnedOff() {
        let doc = FakeDocument()
        let engine = TypingEngine(document: doc)
        engine.autoCapitalize = false
        engine.updateAutoCapitalization()
        engine.type("i")
        XCTAssertEqual(doc.text, "i")
    }

    // MARK: - Field capitalisation modes

    func testWordsModeCapitalizesEveryWord() {
        let doc = FakeDocument()
        let engine = TypingEngine(document: doc)
        engine.capitalizationMode = .words
        engine.updateAutoCapitalization()
        engine.type("j")
        engine.type("an")
        engine.space()
        engine.type("d")
        engine.type("e")
        XCTAssertEqual(doc.text, "Jan De")
    }

    func testAllCharactersMode() {
        let doc = FakeDocument()
        let engine = TypingEngine(document: doc)
        engine.capitalizationMode = .allCharacters
        engine.updateAutoCapitalization()
        engine.type("a")
        engine.type("b")
        XCTAssertEqual(doc.text, "AB")
    }

    func testNoneModeNeverCapitalizes() {
        let doc = FakeDocument()
        let engine = TypingEngine(document: doc)
        engine.capitalizationMode = .none
        engine.updateAutoCapitalization()
        engine.type("x")
        XCTAssertEqual(doc.text, "x")
    }

    func testExternalEditResetsDoubleSpace() {
        let doc = FakeDocument()
        doc.text = "Hoi"
        let engine = TypingEngine(document: doc)
        engine.space()
        doc.insertText("daar ")   // e.g. a suggestion was tapped
        engine.noteExternalEdit()
        engine.space()
        XCTAssertEqual(doc.text, "Hoi daar  ", "no full stop: the last key wasn't space")
    }
}
