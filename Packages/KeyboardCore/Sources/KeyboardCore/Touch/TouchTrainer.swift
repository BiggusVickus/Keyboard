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

/// Sentences for the touch trainer. Together they cover every letter several times.
/// They avoid umlauts and ß, which are on long-press and not part of the touch map.
public enum TrainingSentences {
    public static func all(for language: KeyboardLanguage) -> [String] {
        switch language {
        case .english:
            [
                "The quick brown fox jumps over the lazy dog",
                "Pack my box with five dozen liquor jugs",
                "How vexingly quick daft zebras jump",
                "Sphinx of black quartz judge my vow",
                "We will meet at the station just before six tonight",
                "Could you send me the photos from the weekend",
                "Jackdaws love my big sphinx of quartz",
                "The five boxing wizards jump quickly",
                "I think we should take the train instead of the car",
                "My favourite part of the day is a quiet coffee in the morning",
            ]
        case .dutch:
            [
                "Pa wil zes jaar oude kwik in de grote fles bewaren",
                "Onze excentrieke buurman bakt quiche voor het jaarlijkse feest",
                "Ik kom morgen iets later want de trein heeft vertraging",
                "Wil je straks nog boodschappen doen bij de supermarkt",
                "Het weer is vandaag veel beter dan gisteren",
                "Quinten fietst elke dag zeven kilometer naar zijn werk",
                "Kun je me de foto van het verjaardagsfeest sturen",
                "We gaan in de zomer met de hele familie naar Zeeland",
                "Yara speelt op zaterdag hockey met haar vrienden",
                "Mijn buurvrouw heeft een vrolijke hond met een lange staart",
            ]
        case .german:
            [
                "Franz jagt im komplett verwahrlosten Taxi quer durch Bayern",
                "Xaver und Jakob quatschen im Zug ganz lange",
                "Ich nehme heute lieber den Bus als das Fahrrad",
                "Kannst du mir bitte die Fotos vom Wochenende schicken",
                "Wir treffen uns um sechs Uhr vor dem Bahnhof",
                "Jeden Morgen trinkt Max einen Kaffee mit Milch",
                "Das Wetter ist heute viel besser als gestern",
                "Morgen gehen wir mit der ganzen Familie wandern",
                "Julia zieht im Juni mit ihrem Freund nach Wien",
                "Mein Nachbar hat einen kleinen Hund mit langen Ohren",
            ]
        }
    }

    /// `count` sentences, starting after the ones used last time, so training more adds variety.
    public static func round(for language: KeyboardLanguage, count: Int, startingAt start: Int) -> [String] {
        let sentences = all(for: language)
        return (0..<count).map { sentences[(start + $0) % sentences.count] }
    }
}
