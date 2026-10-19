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

    func testDistantDemonstratives() {
        XCTAssertEqual(fixes("Ik woon in die huis."), ["dat huis"])
        XCTAssertEqual(fixes("Dat auto is snel."), ["Die auto"])
        XCTAssertEqual(fixes("Ik rijd met die huis."), ["dat huis"])
        XCTAssertEqual(fixes("Die huis is mooi."), ["Dat huis"])
        XCTAssertEqual(fixes("Ik woon in die grote huis."), ["dat grote huis"])
    }

    func testDistantDemonstrativesStayQuietWhenTheyMeanWhoOrThat() {
        let correct = [
            "Ik denk dat koffie lekker is.",          // dat = that (conjunction)
            "Er zijn mensen die werk zoeken.",        // die = who
            "Hij zegt dat school leuk is.",
            "Dat kinderen spelen is goed.",           // conjunction at the start, plural
            "Die werk ik morgen af.",                 // die = that one, then verb + subject
            "Deze fiets ik vaak.",
            "Ik woon in die huizen.",                 // die is right for plurals
            "Ik ben er zeker van dat tante Agaath komt.",  // dat = that (conjunction), even after "van"
            "Ik wou dat het nacht was.",              // het = it
            "Officieel heet het overbelasting.",
            "Het kant op de rok was mooi.",           // het kant = lace
        ]
        for sentence in correct {
            XCTAssertEqual(checker.check(sentence), [], sentence)
        }
    }

    func testPlurals() {
        XCTAssertEqual(fixes("Ik lees het kinderen voor."), [])  // het = it: "kinderen" is not after an article here
        XCTAssertEqual(fixes("Dit kinderen zijn lief."), ["Deze kinderen"])
        XCTAssertEqual(fixes("Het meisjes lachen."), ["De meisjes"])
        XCTAssertEqual(fixes("Ik speel met het kinderen."), ["de kinderen"])
        let issue = checker.check("Dit kinderen zijn lief.").first
        XCTAssertTrue(issue?.explanation?.contains("plural") ?? false)
        XCTAssertEqual(issue?.shortMessage, "meervoud")
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
            "Ik doe het zondag.",
            "Het rook lekker.",
            "Het lucht op.",
            "Ik heb het gemaakt.",
            "de goed opgeleide man",
            "Het idee is goed en de idee ook.",
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

    func testWiktionaryDictionary() {
        let dictionary = NounDictionary.dutch
        XCTAssertFalse(dictionary.isEmpty, "DutchNouns.txt must be in the bundle")
        XCTAssertEqual(dictionary.lookup("fietsenstalling"), .de)
        XCTAssertEqual(dictionary.lookup("ziekenhuisbed"), .het)
        XCTAssertEqual(dictionary.lookup("kinderen"), .plural)
        XCTAssertEqual(dictionary.lookup("idee"), .both)
        XCTAssertEqual(dictionary.lookup("weg"), .ambiguous, "also 'away'")
        XCTAssertEqual(dictionary.lookup("rook"), .ambiguous, "also 'smelled'")
        XCTAssertEqual(dictionary.lookup("zondag"), .ambiguous, "Ik doe het zondag")
        XCTAssertNil(dictionary.lookup("qwertyuiop"))
        XCTAssertEqual(dictionary.lookup("Kinderen"), .plural, "lookup ignores case")
    }

    func testDictionaryCatchesRareNouns() {
        XCTAssertEqual(fixes("Ik zag de gevogelte."), ["het gevogelte"])
        XCTAssertEqual(fixes("het hyperlink werkt niet"), ["de hyperlink"])
    }

    func testUnknownCompoundsUseTheirLastPart() {
        XCTAssertEqual(fixes("Ik zie het keukentafelpoot."), ["de keukentafelpoot"])
        XCTAssertEqual(DutchNouns.gender(of: "keukentafelpoot")?.reason, .compound(lastPart: "tafelpoot"))
        XCTAssertEqual(DutchNouns.gender(of: "zorgvervreemding")?.gender, .de, "an -ing word, not a compound of ding")
    }

    func testThingsThatLookLikeErrorsButAreNot() {
        let correct = [
            "Ik woon bij het Binnenhof.",              // a name
            "De Hoge Veluwe is mooi.",
            "Ik ben de fruit- en groenteboer.",        // half a compound
            "Het speelde gitaar.",                     // past tense, not an adjective
            "Het haalde adem.",
            "Toen het afhing van het weer.",           // past tense, not an -ing noun
            "Ik hoorde het krachtige geklapwiek.",     // ge- words are het
            "Ik doe het zometeen.",                    // adverb, not a compound of teen
            "Hij, zij, het inbakte.",                  // past tense, not a compound of akte
            "Het kronkelende pad was lang.",           // participle, not a compound of lende
            "Ik hou van dat armzwaaien.",              // a verb used as a noun, not a plural
            "Ik heb een luxe horloge.",                // luxe doesn't take -e
            "een beetje avontuur",
            "De nummer twee van de wereld won.",       // a player: de
            "Hij is de nummer 1.",
        ]
        for sentence in correct {
            XCTAssertEqual(checker.check(sentence), [], sentence)
        }
    }

    func testAdjectiveBaseFromWiktionary() {
        XCTAssertEqual(NounDictionary.dutch.inflectedAdjectiveBase("grote"), "groot")
        XCTAssertEqual(NounDictionary.dutch.inflectedAdjectiveBase("onbetaalbare"), "onbetaalbaar")
        XCTAssertNil(NounDictionary.dutch.inflectedAdjectiveBase("luxe"))
        XCTAssertEqual(fixes("Dat is een onbetaalbare concept."), ["een onbetaalbaar concept"])
        XCTAssertEqual(fixes("Ik koop een grotere huis."), ["een groter huis"])
    }

    func testBinarySearchOnSmallFile() {
        let dictionary = NounDictionary(text: "aap\td\nauto\td\nbed\th\nbedden\tp\ngrote\ta\tgroot\nzee\td\n")
        XCTAssertEqual(dictionary.lookup("grote"), .adjective)
        XCTAssertEqual(dictionary.inflectedAdjectiveBase("grote"), "groot")
        XCTAssertNil(dictionary.inflectedAdjectiveBase("bed"))
        XCTAssertEqual(dictionary.lookup("aap"), .de)
        XCTAssertEqual(dictionary.lookup("bed"), .het)
        XCTAssertEqual(dictionary.lookup("bedden"), .plural)
        XCTAssertEqual(dictionary.lookup("zee"), .de)
        XCTAssertNil(dictionary.lookup("be"))
        XCTAssertNil(dictionary.lookup("zeeën"))
        XCTAssertNil(dictionary.lookup("a"))
        XCTAssertNil(NounDictionary(text: "").lookup("aap"))
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
