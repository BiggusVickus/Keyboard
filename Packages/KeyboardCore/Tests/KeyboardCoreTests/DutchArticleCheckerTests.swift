import XCTest
@testable import KeyboardCore

final class DutchArticleCheckerTests: XCTestCase {
    private let checker = DutchArticleChecker()

    private func fixes(_ text: String) -> [String] {
        checker.check(text).flatMap(\.replacements)
    }

    func testWrongArticle() {
        XCTAssertEqual(fixes("Ik zie het auto."), ["de auto"])
        XCTAssertEqual(fixes("De huis is groot."), ["Het huis"])
    }

    func testWrongArticleWithAdjective() {
        XCTAssertEqual(fixes("Ik zie de grote huis."), ["het grote huis"])
        XCTAssertEqual(fixes("het rode fiets"), ["de rode fiets"])
    }

    func testDemonstratives() {
        XCTAssertEqual(fixes("Ik wil deze huis."), ["dit huis"])
        XCTAssertEqual(fixes("Dit auto is snel."), ["Deze auto"])
    }

    func testEenWithHetWordDropsTheE() {
        XCTAssertEqual(fixes("Ik heb een grote huis."), ["een groot huis"])
        XCTAssertEqual(fixes("geen mooie boek"), ["geen mooi boek"])
        XCTAssertEqual(fixes("een dikke boek"), ["een dik boek"])
        XCTAssertEqual(fixes("een lieve kind"), ["een lief kind"])
    }

    func testCorrectSentencesStayQuiet() {
        let correct = [
            "Ik woon in het huis naast de auto.",
            "Het meisje leest een boek.",
            "Het grote huis en de grote auto.",
            "Een groot huis en een grote auto.",
            "Ik vind het jammer.",
            "Ik gooi het weg.",
            "We noemen het liefde.",
            "Ik doe het morgen.",
            "de huizen en de boeken",        // plurals always take de
            "het oranje huis en een oranje huis",
            "de oranje auto",
            "een tweede huis",
            "Het Nederlands is moeilijk.",
            "de auto, het huis",
        ]
        for sentence in correct {
            XCTAssertEqual(checker.check(sentence), [], sentence)
        }
    }

    func testPunctuationBreaksTheLink() {
        XCTAssertTrue(checker.check("Wat zie je het, auto?").isEmpty)
    }

    func testRangesPointAtTheText() {
        let text = "Ja. Ik zie het auto"
        let issue = checker.check(text)[0]
        XCTAssertEqual(issue.range.substring(in: text), "het auto")
        XCTAssertEqual(issue.sentence, "Ik zie het auto")
        XCTAssertEqual(issue.topic, .articles)
        XCTAssertTrue(issue.explanation?.contains("de-word") ?? false)
    }

    func testGenderRules() {
        XCTAssertEqual(DutchNouns.gender(of: "huisje")?.gender, .het)
        XCTAssertEqual(DutchNouns.gender(of: "huisje")?.reason, .diminutive)
        XCTAssertEqual(DutchNouns.gender(of: "vrijheid")?.gender, .de)
        XCTAssertEqual(DutchNouns.gender(of: "realisme")?.gender, .het)
        XCTAssertEqual(DutchNouns.gender(of: "voetbalveld")?.reason, .compound(lastPart: "veld"))
        XCTAssertEqual(DutchNouns.gender(of: "natuur")?.gender, .de, "not 'uur' (het)")
        XCTAssertEqual(DutchNouns.gender(of: "avontuur")?.gender, .het, "listed exception to -tuur")
        XCTAssertNil(DutchNouns.gender(of: "belangrijk"), "adjectives aren't compounds")
        XCTAssertNil(DutchNouns.gender(of: "qwerty"))
    }

    func testNoWordIsInBothLists() {
        XCTAssertTrue(DutchNouns.hetWords.isDisjoint(with: DutchNouns.deWords))
    }

    func testUndeclinedAdjectives() {
        let cases = [
            "grote": "groot", "rode": "rood", "gele": "geel", "dikke": "dik", "witte": "wit",
            "lieve": "lief", "boze": "boos", "brave": "braaf", "mooie": "mooi", "nieuwe": "nieuw",
            "kleine": "klein", "oude": "oud", "goede": "goed", "andere": "ander", "lekkere": "lekker",
            "gewone": "gewoon", "normale": "normaal", "grijze": "grijs", "belangrijke": "belangrijk",
            "algemene": "algemeen", "Europese": "Europees", "hele": "heel", "halve": "half",
        ]
        for (inflected, plain) in cases {
            XCTAssertEqual(DutchArticleChecker.undeclined(inflected), plain, inflected)
        }
    }
}
