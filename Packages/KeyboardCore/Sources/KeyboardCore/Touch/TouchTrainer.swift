import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// Runs one touch-training sentence: you type the shown text on the trainer keyboard, and every tap
/// is stored as a sample for the letter that was *meant*, not the key that happened to be hit.
public struct TouchTrainer: Sendable {
    public enum TapResult: Equatable, Sendable {
        /// The tap counted; the trainer moved on to the next character.
        case accepted
        /// Too far from the expected key (probably a different letter). Nothing was recorded.
        case missed
        /// The sentence is complete.
        case finished
    }

    /// The sentence, lowercased, with only characters the trainer keyboard can type.
    public let target: [Character]
    public private(set) var position = 0
    public private(set) var samples: [TouchSample] = []
    public private(set) var misses = 0

    public init(sentence: String, layout: KeyboardLayout) {
        let typable = Set(layout.rows.flatMap { $0 }.compactMap(\.character).joined())
        var chars: [Character] = []
        for character in sentence.lowercased() {
            if character == " " {
                if chars.last != " ", !chars.isEmpty { chars.append(" ") }
            } else if typable.contains(character) {
                chars.append(character)
            }
        }
        while chars.last == " " { chars.removeLast() }
        target = chars
    }

    public var isFinished: Bool { position >= target.count }
    public var expected: Character? { isFinished ? nil : target[position] }
    public var typedText: String { String(target.prefix(position)) }
    public var remainingText: String { String(target.dropFirst(position)) }

    /// Handles a tap at `point` (key-area coordinates) on a keyboard with these frames.
    public mutating func tap(at point: CGPoint, frames: [KeyFrame]) -> TapResult {
        guard let expected else { return .finished }
        let character = String(expected)
        let frame = frames.first {
            if expected == " " { return $0.key.kind == .space }
            return $0.key.character == character
        }
        guard let frame else {
            // A character the layout doesn't have: skip it.
            position += 1
            return isFinished ? .finished : .accepted
        }

        let x = (point.x - frame.rect.midX) / frame.rect.width
        let y = (point.y - frame.rect.midY) / frame.rect.height
        if expected == " " {
            // The space bar is wide; any tap near it counts. Space taps aren't used for the model.
            guard abs(y) < 1.2 else { return miss() }
        } else {
            // Within about one key of the target: a real attempt at it, so learn from it.
            guard abs(x) < 1.3, abs(y) < 1.0 else { return miss() }
            samples.append(TouchSample(character: character, x: x, y: y))
        }
        position += 1
        return isFinished ? .finished : .accepted
    }

    private mutating func miss() -> TapResult {
        misses += 1
        return .missed
    }
}

/// Sentences for the touch trainer. Together they cover every letter many times, plus the period.
/// They only use what the trainer keyboard has: letters, spaces and periods. No commas, question
/// marks, umlauts or ß (those are on other pages or on long-press, and not part of the touch map).
public enum TrainingSentences {
    public static func all(for language: KeyboardLanguage) -> [String] {
        switch language {
        case .english:
            [
                "The quick brown fox jumps over the lazy dog.",
                "Pack my box with five dozen liquor jugs.",
                "How vexingly quick daft zebras jump.",
                "Sphinx of black quartz judge my vow.",
                "Jackdaws love my big sphinx of quartz.",
                "The five boxing wizards jump quickly.",
                "Quick zephyrs blow vexing daft Jim.",
                "Glib jocks quiz nymph to vex dwarf.",
                "Six big devils from Japan quickly forgot how to waltz.",
                "Jim quickly realized that the beautiful gowns are expensive.",
                "The job requires extra pluck and zeal from every young wage earner.",
                "We will meet at the station just before six tonight.",
                "Could you send me the photos from the weekend.",
                "I think we should take the train instead of the car.",
                "My favourite part of the day is a quiet coffee in the morning.",
                "Please remind me to call the dentist tomorrow.",
                "The meeting was moved to Thursday at ten.",
                "She bought fresh bread and a jar of honey at the market.",
                "Our flight leaves early so we need to pack tonight.",
                "Can you pick up some milk on your way home.",
                "The kids built a huge sandcastle at the beach.",
                "He forgot his umbrella and got completely soaked.",
                "Let me know when you arrive at the hotel.",
                "The museum is closed on Mondays.",
                "I am running a little late but I will be there soon.",
                "We watched an old movie and ate way too much popcorn.",
                "The quiet lake reflected the mountains perfectly.",
                "Just text me the address and I will find it.",
                "Thank you so much for the lovely dinner last night.",
                "I need to renew my passport before the summer.",
                "The train was delayed by twenty minutes again.",
                "Do not forget to water the plants while I am away.",
                "Happy birthday and enjoy your special day.",
                "The new bakery on the corner makes amazing croissants.",
                "Could we move our call to next week.",
                "My brother lives in a small village near the coast.",
                "The weather forecast says it will snow on Sunday.",
                "I left my keys on the kitchen table.",
                "Every morning I walk the dog along the river.",
                "The project deadline is at the end of the month.",
                "We should book the tickets before they sell out.",
                "Zoe quickly fixed the broken jukebox at the party.",
                "Max visited the zoo and saw a lazy jaguar.",
                "Ten quiet foxes jumped over seven sleepy dogs.",
                "It was late. We went home.",
                "Call me later. I am in a meeting.",
                "The shop opens at nine. Please do not be late.",
                "Dinner is ready. Come and eat while it is warm.",
                "I found a great recipe for vegetable soup.",
                "The jazz band played until well after midnight.",
                "Quinn packed six boxes of books for the move.",
                "Our neighbours are having a barbecue on Saturday.",
            ]
        case .dutch:
            [
                "Pa wil zes jaar oude kwik in de grote fles bewaren.",
                "Onze excentrieke buurman bakt quiche voor het jaarlijkse feest.",
                "Ik kom morgen iets later want de trein heeft vertraging.",
                "Wil je straks nog boodschappen doen bij de supermarkt.",
                "Het weer is vandaag veel beter dan gisteren.",
                "Quinten fietst elke dag zeven kilometer naar zijn werk.",
                "Kun je me de foto van het verjaardagsfeest sturen.",
                "We gaan in de zomer met de hele familie naar Zeeland.",
                "Yara speelt op zaterdag hockey met haar vrienden.",
                "Mijn buurvrouw heeft een vrolijke hond met een lange staart.",
            ]
        case .german:
            [
                "Franz jagt im komplett verwahrlosten Taxi quer durch Bayern.",
                "Xaver und Jakob quatschen im Zug ganz lange.",
                "Ich nehme heute lieber den Bus als das Fahrrad.",
                "Kannst du mir bitte die Fotos vom Wochenende schicken.",
                "Wir treffen uns um sechs Uhr vor dem Bahnhof.",
                "Jeden Morgen trinkt Max einen Kaffee mit Milch.",
                "Das Wetter ist heute viel besser als gestern.",
                "Morgen gehen wir mit der ganzen Familie wandern.",
                "Julia zieht im Juni mit ihrem Freund nach Wien.",
                "Mein Nachbar hat einen kleinen Hund mit langen Ohren.",
                "Bitte ruf mich an wenn du angekommen bist.",
                "Der Termin wurde auf Donnerstag verschoben.",
                "Wir haben am Wochenende einen Ausflug an den See gemacht.",
                "Kannst du auf dem Heimweg noch Brot kaufen.",
                "Die Kinder spielen den ganzen Nachmittag im Garten.",
                "Ich habe meinen Schirm im Auto vergessen.",
                "Das Konzert beginnt um acht Uhr abends.",
                "Meine Schwester wohnt in einem kleinen Dorf am Meer.",
                "Wir brauchen noch Eier und Butter.",
                "Am Sonntag soll es den ganzen Tag regnen.",
                "Kommst du heute Abend mit ins Kino.",
                "Ich lerne jeden Tag eine halbe Stunde Spanisch.",
                "Das Paket kommt wahrscheinlich erst am Montag.",
                "Sylvia wohnt seit zwei Jahren in Zwickau.",
                "Quirin fotografiert gern alte Kirchen.",
                "Jens kocht heute Abend eine scharfe Suppe.",
                "Zwanzig Boxer joggen quer durch den Park.",
                "Der Hund wartet geduldig vor dem Haus.",
                "Wir fahren im August mit dem Wohnmobil nach Italien.",
                "Ich habe meine Tasche im Zug liegen lassen.",
                "Bitte schick mir die Adresse per Nachricht.",
                "Das Restaurant am Markt hat jetzt einen neuen Koch.",
                "Die Bibliothek ist am Montag geschlossen.",
                "Ein Taxi fuhr quer durch die volle Innenstadt.",
                "Jakob will im Winter Ski fahren lernen.",
                "Vom Balkon aus sieht man die ganze Stadt.",
                "Max und Felix bauen zusammen ein Baumhaus.",
                "Die Katze liegt den ganzen Tag in der Sonne.",
                "Kannst du mir heute helfen den Schrank aufzubauen.",
                "Halte die Leertaste lange fest um den Cursor zu bewegen.",
                "Es war ein langer Tag. Ich gehe jetzt schlafen.",
                "Ruf mich bitte an. Es ist wichtig.",
                "Der Laden macht um neun auf. Wir treffen uns davor.",
                "Das Essen ist fertig. Komm bitte schnell an den Tisch.",
                "Wir wollen im Herbst eine Radtour an der Elbe machen.",
                "Der Zoo hat zwei neue Pinguine bekommen.",
                "Ich warte vor dem Kino auf dich.",
                "Die Party war toll. Alle haben lange getanzt.",
                "Felix spielt jeden Freitag mit seinen Freunden Tennis.",
                "Quax will im Sommer zum ersten Mal segeln.",
                "Viktor bringt morgen Kuchen mit zur Arbeit.",
            ]
        }
    }

    /// `count` sentences, starting after the ones used last time, so training more adds variety.
    public static func round(for language: KeyboardLanguage, count: Int, startingAt start: Int) -> [String] {
        let sentences = all(for: language)
        return (0..<count).map { sentences[(start + $0) % sentences.count] }
    }
}
