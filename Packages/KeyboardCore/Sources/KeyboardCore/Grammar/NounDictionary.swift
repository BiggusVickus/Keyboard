import Foundation

/// The large Dutch word list: about 240,000 nouns and plurals with de/het, plus adjective forms
/// and other words that must never be read as nouns. Built from Wiktionary (CC BY-SA 4.0) by
/// Tools/build_dutch_nouns.py. The file is memory-mapped and binary-searched, so it costs
/// almost no RAM in the keyboard.
/// Format: sorted lines "word<TAB>code" (adjectives add "<TAB>base form").
public final class NounDictionary: @unchecked Sendable {
    public enum Entry: UInt8, Sendable {
        case de = 0x64          // "d"
        case het = 0x68         // "h"
        case plural = 0x70      // "p": always de
        /// Both are correct (de/het idee): never flag.
        case both = 0x62        // "b"
        /// Also another kind of word (weg, rook, licht, meteen): never flag.
        case ambiguous = 0x78   // "x"
        /// An adjective with the -e ending (grote); the file also holds the form without it.
        case adjective = 0x61   // "a"
    }

    public static let dutch = NounDictionary(url: Bundle.module.url(forResource: "DutchNouns", withExtension: "txt"))

    private let data: Data

    init(url: URL?) {
        data = url.flatMap { try? Data(contentsOf: $0, options: .alwaysMapped) } ?? Data()
    }

    /// For tests: the same format as the file.
    init(text: String) {
        data = Data(text.utf8)
    }

    public var isEmpty: Bool { data.isEmpty }

    public func lookup(_ word: String) -> Entry? {
        find(word)?.entry
    }

    /// "grote" → "groot", "grotere" → "groter". Nil if the word isn't an inflected adjective.
    public func inflectedAdjectiveBase(_ word: String) -> String? {
        guard let found = find(word), found.entry == .adjective else { return nil }
        return found.extra
    }

    private func find(_ word: String) -> (entry: Entry, extra: String?)? {
        let key = Array(word.lowercased().utf8)
        return data.withUnsafeBytes { raw -> (entry: Entry, extra: String?)? in
            let bytes = raw.bindMemory(to: UInt8.self)
            let newline: UInt8 = 10, tab: UInt8 = 9
            var low = 0, high = bytes.count
            // `low` and `high` are always at the start of a line (or the end of the file).
            while low < high {
                var start = (low + high) / 2
                while start > low, bytes[start - 1] != newline { start -= 1 }
                var keyEnd = start
                while keyEnd < bytes.count, bytes[keyEnd] != tab, bytes[keyEnd] != newline { keyEnd += 1 }
                var lineEnd = keyEnd
                while lineEnd < bytes.count, bytes[lineEnd] != newline { lineEnd += 1 }

                switch Self.compare(key, bytes, start..<keyEnd) {
                case 0:
                    guard keyEnd + 1 < lineEnd, let entry = Entry(rawValue: bytes[keyEnd + 1]) else { return nil }
                    // Optional third column, after "code<TAB>".
                    let extraStart = keyEnd + 3
                    let extra = extraStart < lineEnd
                        ? String(decoding: UnsafeBufferPointer(rebasing: bytes[extraStart..<lineEnd]), as: UTF8.self)
                        : nil
                    return (entry, extra)
                case ..<0:
                    high = start
                default:
                    low = lineEnd + 1
                }
            }
            return nil
        }
    }

    /// Byte-wise comparison, the same order the file is sorted in.
    private static func compare(_ key: [UInt8], _ bytes: UnsafeBufferPointer<UInt8>, _ range: Range<Int>) -> Int {
        var i = 0
        var j = range.lowerBound
        while i < key.count, j < range.upperBound {
            if key[i] != bytes[j] { return key[i] < bytes[j] ? -1 : 1 }
            i += 1
            j += 1
        }
        if i == key.count, j == range.upperBound { return 0 }
        return i == key.count ? -1 : 1
    }
}
