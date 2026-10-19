import Foundation

/// Runs the grammar checks for a piece of text: the offline de/het check for Dutch,
/// plus LanguageTool when it is available. Remembers recent results so retyping the same
/// text doesn't cost another request.
public actor GrammarChecker {
    private let articles = DutchArticleChecker()
    private var cache: [String: GrammarResult] = [:]
    private var cacheOrder: [String] = []
    private static let cacheSize = 20

    public init() {}

    /// - Parameter languageTool: nil when there is no network (no Full Access) or no valid URL.
    public func check(_ text: String, language: KeyboardLanguage, level: GrammarLevel,
                      languageTool: LanguageToolClient?) async -> GrammarResult {
        let key = "\(language.rawValue)|\(level.rawValue)|\(languageTool != nil)|\(text)"
        if let cached = cache[key] { return cached }

        let local = language == .dutch ? articles.check(text) : []
        var remote: [GrammarIssue] = []
        var warning: String?
        if let languageTool {
            do {
                remote = try await languageTool.check(text, language: language, level: level)
            } catch let error as GrammarCheckError {
                warning = error.message
            } catch is CancellationError {
                return GrammarResult(text: text, language: language, issues: local)
            } catch {
                warning = "No connection to LanguageTool"
            }
        }

        let result = GrammarResult(text: text, language: language,
                                   issues: Self.merge(local: local, remote: remote), warning: warning)
        // Don't cache failures: the next try may work.
        if warning == nil { remember(result, key: key) }
        return result
    }

    /// Local issues win where both found something: they come with an English explanation.
    static func merge(local: [GrammarIssue], remote: [GrammarIssue]) -> [GrammarIssue] {
        let kept = remote.filter { issue in !local.contains { $0.range.overlaps(issue.range) } }
        return (local + kept).sorted { $0.range.location < $1.range.location }
    }

    private func remember(_ result: GrammarResult, key: String) {
        cache[key] = result
        cacheOrder.append(key)
        if cacheOrder.count > Self.cacheSize {
            cache[cacheOrder.removeFirst()] = nil
        }
    }
}
