import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum GrammarCheckError: Error, Equatable {
    case invalidURL
    case rateLimited
    case server(status: Int)

    /// Short text for the suggestion bar.
    public var message: String {
        switch self {
        case .invalidURL: "Check the LanguageTool URL in Settings"
        case .rateLimited: "LanguageTool is busy, trying again soon"
        case .server(let status): "LanguageTool error \(status)"
        }
    }
}

/// Talks to a LanguageTool server (the free public one, or your own).
/// API: https://languagetool.org/http-api/
public struct LanguageToolClient: Sendable {
    public let endpoint: URL
    private let http: HTTPClient

    /// Returns nil when `urlString` isn't a usable URL.
    public init?(urlString: String, http: HTTPClient = URLSessionHTTPClient()) {
        guard let url = URL(string: urlString.trimmingCharacters(in: .whitespaces)),
              let scheme = url.scheme, scheme == "https" || scheme == "http"
        else { return nil }
        self.endpoint = url
        self.http = http
    }

    public func check(_ text: String, language: KeyboardLanguage, level: GrammarLevel) async throws -> [GrammarIssue] {
        let (data, response) = try await http.send(makeRequest(text: text, language: language, level: level))
        switch response.statusCode {
        case 200: break
        case 429: throw GrammarCheckError.rateLimited
        default: throw GrammarCheckError.server(status: response.statusCode)
        }
        return try Self.parse(data, text: text, language: language, level: level)
    }

    func makeRequest(text: String, language: KeyboardLanguage, level: GrammarLevel) -> URLRequest {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 10
        request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        var fields = [("text", text), ("language", language.languageToolCode)]
        // Lets LanguageTool spot English "false friends" in Dutch and German.
        if language != .english { fields.append(("motherTongue", "en-US")) }
        // "picky" turns on extra style rules; only wanted at the Polish level.
        if level == .polish { fields.append(("level", "picky")) }
        request.httpBody = Self.formEncode(fields)
        return request
    }

    static func formEncode(_ fields: [(String, String)]) -> Data {
        let allowed = CharacterSet(charactersIn:
            "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        let body = fields.map { key, value in
            let encoded = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
            return "\(key)=\(encoded)"
        }.joined(separator: "&")
        return Data(body.utf8)
    }

    // MARK: - Response

    private struct Response: Decodable {
        let matches: [Match]
    }

    private struct Match: Decodable {
        let message: String
        let shortMessage: String?
        let replacements: [Replacement]
        let offset: Int
        let length: Int
        let sentence: String?
        let rule: Rule
    }

    private struct Replacement: Decodable {
        let value: String
    }

    private struct Rule: Decodable {
        let id: String
        let issueType: String?
        let category: Category?
    }

    private struct Category: Decodable {
        let id: String?
    }

    static func parse(_ data: Data, text: String, language: KeyboardLanguage, level: GrammarLevel) throws -> [GrammarIssue] {
        let response = try JSONDecoder().decode(Response.self, from: data)
        return response.matches.compactMap { match in
            let range = UTF16Range(location: match.offset, length: match.length)
            guard let covered = range.substring(in: text) else { return nil }

            let issueKind = Self.kind(issueType: match.rule.issueType, categoryID: match.rule.category?.id)
            if issueKind == .tip, !level.showsImprovements { return nil }

            return GrammarIssue(
                range: range,
                text: covered,
                message: match.message,
                shortMessage: match.shortMessage ?? "",
                replacements: Array(match.replacements.map(\.value).prefix(5)),
                ruleID: match.rule.id,
                kind: issueKind,
                source: .languageTool,
                topic: GrammarTopic.classify(ruleID: match.rule.id, categoryID: match.rule.category?.id,
                                             issueType: match.rule.issueType, message: match.message,
                                             language: language),
                sentence: match.sentence ?? text
            )
        }
    }

    /// Style and register suggestions are optional tips; everything else is an error.
    static func kind(issueType: String?, categoryID: String?) -> GrammarIssue.Kind {
        let tipTypes: Set<String> = ["style", "register", "locale-violation"]
        let tipCategories: Set<String> = ["STYLE", "REDUNDANCY", "COLLOQUIALISMS", "PLAIN_ENGLISH", "GENDER_NEUTRALITY"]
        if let issueType, tipTypes.contains(issueType) { return .tip }
        if let categoryID, tipCategories.contains(categoryID) { return .tip }
        return .error
    }
}
