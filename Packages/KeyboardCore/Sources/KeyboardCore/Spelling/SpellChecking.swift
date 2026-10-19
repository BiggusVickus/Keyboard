import Foundation

/// A dictionary to check words against. In the keyboard this is Apple's `UITextChecker`
/// (plus contacts and text shortcuts); in tests it is a small word list.
public protocol SpellChecking {
    /// True if the word is spelled correctly.
    func isKnown(_ word: String, language: KeyboardLanguage) -> Bool
    /// Likely corrections for a misspelled word, best first.
    func corrections(for word: String, language: KeyboardLanguage) -> [String]
    /// Ways to finish a partly typed word, most likely first.
    func completions(for prefix: String, language: KeyboardLanguage) -> [String]
}

public enum EditDistance {
    /// Number of single-letter edits (insert, delete, replace, swap two neighbours) to turn `a` into `b`.
    public static func between(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }

        var d = Array(repeating: Array(repeating: 0, count: b.count + 1), count: a.count + 1)
        for i in 0...a.count { d[i][0] = i }
        for j in 0...b.count { d[0][j] = j }
        for i in 1...a.count {
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                d[i][j] = min(d[i - 1][j] + 1, d[i][j - 1] + 1, d[i - 1][j - 1] + cost)
                if i > 1, j > 1, a[i - 1] == b[j - 2], a[i - 2] == b[j - 1] {
                    d[i][j] = min(d[i][j], d[i - 2][j - 2] + 1)
                }
            }
        }
        return d[a.count][b.count]
    }
}
