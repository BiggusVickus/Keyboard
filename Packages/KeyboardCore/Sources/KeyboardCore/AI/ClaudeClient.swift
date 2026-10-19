import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Calls the Claude Messages API directly over HTTPS (there is no official Swift SDK).
/// Docs: https://platform.claude.com/docs/en/api/messages
public struct ClaudeClient: AIClient {
    public static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    static let apiVersion = "2023-06-01"

    public let apiKey: String
    public let model: String
    private let http: HTTPClient

    public init(apiKey: String, model: String, http: HTTPClient = URLSessionHTTPClient()) {
        self.apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        self.model = model.trimmingCharacters(in: .whitespacesAndNewlines)
        self.http = http
    }

    public func complete(_ request: AIRequest) async throws -> String {
        guard !apiKey.isEmpty else {
            throw AIError.notConfigured("Add your Claude API key in the Taalhulp app (Settings → AI helper).")
        }
        guard !model.isEmpty else {
            throw AIError.notConfigured("Choose a Claude model in the Taalhulp app (Settings → AI helper).")
        }

        let (data, response) = try await http.send(try makeRequest(request))
        guard response.statusCode == 200 else {
            throw AIError.http(status: response.statusCode, message: Self.errorMessage(from: data))
        }
        return try Self.parse(data)
    }

    func makeRequest(_ request: AIRequest) throws -> URLRequest {
        var body: [String: Any] = [
            "model": model,
            "max_tokens": request.maxTokens,
            "system": request.system,
            "messages": [["role": "user", "content": request.prompt]],
        ]

        var outputConfig: [String: Any] = [:]
        if Self.supportsEffort(model) { outputConfig["effort"] = request.effort.rawValue }
        if let schema = request.schema,
           let schemaObject = try? JSONSerialization.jsonObject(with: Data(schema.utf8)) {
            // Structured output: the answer is guaranteed to be JSON matching the schema.
            outputConfig["format"] = ["type": "json_schema", "schema": schemaObject]
        }
        if !outputConfig.isEmpty { body["output_config"] = outputConfig }

        var urlRequest = URLRequest(url: Self.endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = 60
        urlRequest.setValue("application/json", forHTTPHeaderField: "content-type")
        urlRequest.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        urlRequest.setValue(Self.apiVersion, forHTTPHeaderField: "anthropic-version")

        if Self.supportsServerFallback(model) {
            // If the model's safety filter declines a (harmless) request, the API retries it
            // on a suitable other model instead of returning a refusal.
            body["fallbacks"] = "default"
            urlRequest.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
        }

        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)
        return urlRequest
    }

    /// Models that accept `output_config.effort`.
    static func supportsEffort(_ model: String) -> Bool {
        let prefixes = ["claude-fable-5", "claude-mythos-5", "claude-opus-5", "claude-sonnet-5", "claude-haiku-5",
                        "claude-opus-4-6", "claude-opus-4-7", "claude-opus-4-8", "claude-sonnet-4-6"]
        return prefixes.contains { model.hasPrefix($0) }
    }

    /// Models that accept `fallbacks: "default"`.
    static func supportsServerFallback(_ model: String) -> Bool {
        ["claude-fable-5-1", "claude-opus-5-5", "claude-opus-5", "claude-sonnet-5-5"].contains(model)
    }

    // MARK: - Response

    private struct Response: Decodable {
        struct Block: Decodable {
            let type: String
            let text: String?
        }
        let content: [Block]
        let stop_reason: String?
    }

    private struct ErrorResponse: Decodable {
        struct Detail: Decodable {
            let type: String
            let message: String
        }
        let error: Detail
    }

    static func parse(_ data: Data) throws -> String {
        guard let response = try? JSONDecoder().decode(Response.self, from: data) else {
            throw AIError.invalidResponse
        }
        // Check why it stopped before reading the content.
        switch response.stop_reason {
        case "refusal": throw AIError.refused
        case "max_tokens": throw AIError.truncated
        default: break
        }
        // Only text blocks are the answer; thinking and fallback blocks are skipped.
        let text = response.content
            .filter { $0.type == "text" }
            .compactMap(\.text)
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw AIError.emptyResponse }
        return text
    }

    static func errorMessage(from data: Data) -> String {
        (try? JSONDecoder().decode(ErrorResponse.self, from: data))?.error.message ?? ""
    }
}
