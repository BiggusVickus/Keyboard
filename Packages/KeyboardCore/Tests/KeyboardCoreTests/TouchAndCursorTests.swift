import XCTest
@testable import KeyboardCore

final class AlternatesTests: XCTestCase {
    private func key(_ char: String, _ layout: KeyboardLayout) -> Key? {
        layout.rows.flatMap { $0 }.first { $0.kind == .character(char) }
    }

    func testNumberAndSymbolPagesHaveLongPress() {
        let numbers = KeyboardLayout.make(language: .english, page: .numbers, showsGlobe: false)
        XCTAssertEqual(key("0", numbers)?.alternates, ["°"])
        XCTAssertEqual(key("!", numbers)?.alternates, ["¡"])
        XCTAssertEqual(key("?", numbers)?.alternates, ["¿"])
        XCTAssertTrue(key("€", numbers)?.alternates.contains("$") ?? false)
        let symbols = KeyboardLayout.make(language: .english, page: .symbols, showsGlobe: false)
        XCTAssertTrue(key("$", symbols)?.alternates.contains("€") ?? false)
    }

    func testPeriodNextToSpaceWithLocalUrlEndings() {
        for (language, first) in [(KeyboardLanguage.dutch, ".nl"), (.german, ".de"), (.english, ".com")] {
            let layout = KeyboardLayout.make(language: language, page: .letters, showsGlobe: false)
            let bottom = layout.rows.last!
            let space = bottom.firstIndex { $0.kind == .space }!
            XCTAssertEqual(bottom[space + 1].kind, .character("."), "period right of the space bar")
            XCTAssertEqual(bottom[space + 1].alternates.first, first)
            XCTAssertTrue(bottom[space + 1].alternates.contains(".com"))
        }
    }

    func testEveryLanguageHasCommonAccents() {
        for language in KeyboardLanguage.allCases {
            let layout = KeyboardLayout.make(language: language, page: .letters, showsGlobe: false)
            XCTAssertTrue(key("e", layout)?.alternates.contains("é") ?? false)
            XCTAssertTrue(key("n", layout)?.alternates.contains("ñ") ?? false)
            XCTAssertTrue(key("z", layout)?.alternates.contains("ž") ?? false)
            let alternates = key("a", layout)!.alternates
            XCTAssertEqual(alternates.count, Set(alternates).count, "no duplicates")
        }
    }

    func testLiteralInsertIgnoresShift() {
        let buffer = TextBuffer("")
        let engine = TypingEngine(document: buffer)
        engine.updateAutoCapitalization()
        XCTAssertEqual(engine.shift, .once)
        engine.insertLiteral(".com")
        XCTAssertEqual(buffer.text, ".com")
    }
}

final class GeometryAndHitTests: XCTestCase {
    private let layout = KeyboardLayout.make(language: .english, page: .letters, showsGlobe: false)
    private lazy var frames = KeyboardGeometry.frames(for: layout, width: 390)

    private func frame(_ char: String) -> KeyFrame {
        frames.first { $0.key.character == char }!
    }

    func testFramesFitAndDontOverlap() {
        for frame in frames {
            XCTAssertGreaterThanOrEqual(frame.rect.minX, 0)
            XCTAssertLessThanOrEqual(frame.rect.maxX, 390.001)
        }
        let q = frame("q"), w = frame("w")
        XCTAssertEqual(w.rect.minX - q.rect.maxX, KeyboardMetrics.keySpacing, accuracy: 0.001)
        XCTAssertEqual(frame("p").rect.maxX, 390 - KeyboardMetrics.horizontalPadding, accuracy: 0.001)
    }

    func testNoFramesBeforeThereIsAWidth() {
        XCTAssertTrue(KeyboardGeometry.frames(for: layout, width: 0).isEmpty)
        XCTAssertTrue(KeyboardGeometry.frames(for: layout, width: 40).isEmpty)
    }

    func testGapsGoToTheNearestKey() {
        let tester = KeyHitTester(kind: .normal)
        let q = frame("q"), w = frame("w")
        // 1 pt right of q, in the gap.
        let nearQ = CGPoint(x: q.rect.maxX + 1, y: q.rect.midY)
        XCTAssertEqual(tester.frame(at: nearQ, in: frames)?.key.character, "q")
        let nearW = CGPoint(x: w.rect.minX - 1, y: w.rect.midY)
        XCTAssertEqual(tester.frame(at: nearW, in: frames)?.key.character, "w")
        // Between two rows.
        let a = frame("a")
        let betweenRows = CGPoint(x: a.rect.midX, y: a.rect.minY - 2)
        XCTAssertEqual(tester.frame(at: betweenRows, in: frames)?.key.character, "a")
    }

    func testLargerLettersReachIntoShift() {
        let z = frame("z")
        let shift = frames.first { $0.key.kind == .shift }!
        let insideShiftNearZ = CGPoint(x: shift.rect.maxX - 4, y: shift.rect.midY)
        let deepInShift = CGPoint(x: shift.rect.maxX - 10, y: shift.rect.midY)
        XCTAssertEqual(KeyHitTester(kind: .larger).frame(at: deepInShift, in: frames)?.key.kind, .shift)
        let space = frames.first { $0.key.kind == .space }!
        let topOfSpace = CGPoint(x: space.rect.midX, y: space.rect.minY + 3)
        XCTAssertEqual(KeyHitTester(kind: .normal).frame(at: topOfSpace, in: frames)?.key.kind, .space)
        XCTAssertNotNil(KeyHitTester(kind: .larger).frame(at: topOfSpace, in: frames)?.key.character)
        XCTAssertEqual(KeyHitTester(kind: .normal).frame(at: insideShiftNearZ, in: frames)?.key.kind, .shift)
        XCTAssertEqual(KeyHitTester(kind: .larger).frame(at: insideShiftNearZ, in: frames)?.key.character, "z")
        _ = z
    }

    func testCustomModelLearnsOffsets() {
        // This person hits "e" far to the right (0.6 keys), almost on "r".
        var profile = TouchProfile()
        for i in 0..<30 {
            profile.add(TouchSample(character: "e", x: 0.6 + Double(i % 3) * 0.02, y: 0))
            profile.add(TouchSample(character: "r", x: 0 + Double(i % 3) * 0.02, y: 0))
        }
        let e = frame("e")
        let tap = CGPoint(x: e.rect.midX + e.rect.width * 0.62, y: e.rect.midY)
        XCTAssertEqual(KeyHitTester(kind: .normal).frame(at: tap, in: frames)?.key.character, "r")
        XCTAssertEqual(KeyHitTester(kind: .custom, profile: profile).frame(at: tap, in: frames)?.key.character, "e")
    }

    func testUntrainedCustomBehavesLikeNormal() {
        let custom = KeyHitTester(kind: .custom, profile: TouchProfile())
        let normal = KeyHitTester(kind: .normal)
        for x in stride(from: 0.0, through: 390, by: 7) {
            for y in stride(from: 0.0, through: KeyboardMetrics.keyAreaHeight, by: 7) {
                let point = CGPoint(x: x, y: y)
                XCTAssertEqual(custom.frame(at: point, in: frames)?.key.id,
                               normal.frame(at: point, in: frames)?.key.id, "at \(point)")
            }
        }
    }

    func testProfileKeepsNewestSamplesAndRoundTrips() {
        var profile = TouchProfile()
        for i in 0..<(TouchProfile.maxSamples + 10) {
            profile.add(TouchSample(character: "a", x: Double(i), y: 0))
        }
        XCTAssertEqual(profile.samples.count, TouchProfile.maxSamples)
        XCTAssertEqual(profile.samples.last?.x, Double(TouchProfile.maxSamples + 9))

        let store = TouchProfileStore(defaults: UserDefaults(suiteName: "TouchTests-\(UUID())")!)
        store.save(profile)
        XCTAssertEqual(store.load(), profile)
    }

    func testTrainerRecordsMeantLetterAndRejectsWildTaps() {
        var trainer = TouchTrainer(sentence: "Hé, an!", layout: layout)
        XCTAssertEqual(String(trainer.target), "h an", "lowercase, only typable characters")

        let h = frame("h")
        XCTAssertEqual(trainer.tap(at: CGPoint(x: h.rect.midX + 5, y: h.rect.midY), frames: frames), .accepted)
        XCTAssertEqual(trainer.samples.first?.character, "h")
        XCTAssertEqual(trainer.samples.first!.x, 5 / h.rect.width, accuracy: 0.0001)

        // Expected space; a tap on the top row is a miss.
        XCTAssertEqual(trainer.tap(at: frame("q").center, frames: frames), .missed)
        let space = frames.first { $0.key.kind == .space }!
        XCTAssertEqual(trainer.tap(at: space.center, frames: frames), .accepted)
        // "a" expected, tapping "p" (far away) doesn't count.
        XCTAssertEqual(trainer.tap(at: frame("p").center, frames: frames), .missed)
        XCTAssertEqual(trainer.tap(at: frame("a").center, frames: frames), .accepted)
        XCTAssertEqual(trainer.tap(at: frame("n").center, frames: frames), .finished)
        XCTAssertEqual(trainer.samples.map(\.character), ["h", "a", "n"])
        XCTAssertEqual(trainer.misses, 2)
    }

    func testTrainingSentencesCoverEveryLetter() {
        for language in KeyboardLanguage.allCases {
            let text = TrainingSentences.all(for: language).joined().lowercased()
            for letter in "abcdefghijklmnopqrstuvwxyz" {
                XCTAssertTrue(text.contains(letter), "\(language) is missing \(letter)")
            }
        }
    }
}

final class CursorMovementTests: XCTestCase {
    func testLeftRightStepOverEmoji() {
        XCTAssertEqual(CursorMovement.left(before: "hi👍"), -2)
        XCTAssertEqual(CursorMovement.left(before: ""), 0)
        XCTAssertEqual(CursorMovement.right(after: "a"), 1)
        XCTAssertEqual(CursorMovement.right(after: ""), 0)
    }

    func testUpGoesToSameColumnOnPreviousLine() {
        let buffer = TextBuffer("hello world\nabc")
        let offset = CursorMovement.up(before: buffer.beforeCursor, lineLength: 40)
        buffer.adjustTextPosition(byCharacterOffset: offset)
        XCTAssertEqual(buffer.beforeCursor, "hel")
    }

    func testUpClampsToShortLine() {
        let buffer = TextBuffer("ab\nhello")
        buffer.adjustTextPosition(byCharacterOffset: CursorMovement.up(before: buffer.beforeCursor, lineLength: 40))
        XCTAssertEqual(buffer.beforeCursor, "ab")
    }

    func testUpOnFirstLineStaysPut() {
        XCTAssertEqual(CursorMovement.up(before: "hello", lineLength: 40), 0)
    }

    func testUpInsideWrappedParagraph() {
        XCTAssertEqual(CursorMovement.up(before: String(repeating: "a", count: 50), lineLength: 40), -40)
    }

    func testDownGoesToSameColumnOnNextLine() {
        let buffer = TextBuffer("abc\nhello world")
        buffer.adjustTextPosition(byCharacterOffset: -15)  // cursor at start
        buffer.adjustTextPosition(byCharacterOffset: 2)    // after "ab"
        let offset = CursorMovement.down(before: buffer.beforeCursor, after: buffer.afterCursor, lineLength: 40)
        buffer.adjustTextPosition(byCharacterOffset: offset)
        XCTAssertEqual(buffer.beforeCursor, "abc\nhe")
    }

    func testDownOnLastLineStaysPut() {
        XCTAssertEqual(CursorMovement.down(before: "ab", after: "cde", lineLength: 40), 0)
    }

    func testTrackpadCursorFollowsItsOwnSteps() {
        // Three lines; start at the end of "world".
        let cursor = TrackpadCursor(before: "one\ntwo\nworld", after: "")
        XCTAssertEqual(cursor.step(.up, lineLength: 40), -6)  // to the end of "two"
        XCTAssertEqual(cursor.before, "one\ntwo")
        XCTAssertEqual(cursor.step(.up, lineLength: 40), -4)  // to the end of "one"
        XCTAssertEqual(cursor.step(.up, lineLength: 40), 0)   // first line: stays
        XCTAssertEqual(cursor.step(.left, lineLength: 40), -1)
        XCTAssertEqual(cursor.before, "on")
        XCTAssertEqual(cursor.after, "e\ntwo\nworld")
        XCTAssertEqual(cursor.step(.down, lineLength: 40), 4)  // "tw|o"
        XCTAssertEqual(cursor.before, "one\ntw")
    }
}

final class AppGroupTests: XCTestCase {
    func testPicksBaseOrTeamSuffixedGroup() {
        let base = SettingsStore.baseAppGroupID
        XCTAssertEqual(SettingsStore.pickAppGroup(from: [base]), base)
        // plumesign: the shared group gets ".TEAMID"; each bundle also gets its own default group.
        let resigned = ["\(base).keyboard.ABCDE12345", "\(base).ABCDE12345"]
        XCTAssertEqual(SettingsStore.pickAppGroup(from: resigned), "\(base).ABCDE12345")
        XCTAssertNil(SettingsStore.pickAppGroup(from: ["group.other"]))
    }

    func testReadsGroupsFromProvisioningProfile() {
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <plist version="1.0"><dict><key>Entitlements</key><dict>
        <key>com.apple.security.application-groups</key><array><string>group.x.TEAM</string></array>
        </dict></dict></plist>
        """
        var data = Data([0x30, 0x82, 0x01])  // CMS bytes before the XML
        data.append(Data(plist.utf8))
        data.append(Data([0x00, 0xA0]))
        XCTAssertEqual(SettingsStore.appGroups(inProvisioningProfile: data), ["group.x.TEAM"])
    }
}

final class TextExpansionTests: XCTestCase {
    private let list = [TextExpansion(shortcut: "mvg", expansion: "met vriendelijke groet,"),
                        TextExpansion(shortcut: "Adr", expansion: "Keizersgracht 1, Amsterdam")]

    func testMatchesIgnoringCase() {
        XCTAssertEqual(TextExpander.match("MVG", in: list)?.shortcut, "mvg")
        XCTAssertEqual(TextExpander.match("adr", in: list)?.shortcut, "Adr")
        XCTAssertNil(TextExpander.match("mv", in: list))
        XCTAssertNil(TextExpander.match("", in: list))
    }

    func testCapitalisedShortcutCapitalisesExpansion() {
        XCTAssertEqual(TextExpander.expandedText(for: "Mvg", using: list[0]), "Met vriendelijke groet,")
        XCTAssertEqual(TextExpander.expandedText(for: "mvg", using: list[0]), "met vriendelijke groet,")
    }

    func testCleanAndAdd() {
        XCTAssertEqual(TextExpander.cleanShortcut(" b.t w! "), "btw")
        let updated = TextExpander.adding(TextExpansion(shortcut: "MVG", expansion: "groetjes"), to: list)
        XCTAssertEqual(updated.count, 2)
        XCTAssertEqual(TextExpander.match("mvg", in: updated)?.expansion, "groetjes")
    }
}
