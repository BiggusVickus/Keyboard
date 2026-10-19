import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Talks to a local server with an OpenAI-style `/chat/completions` endpoint,
/// such as Ollama or LM Studio on your Mac.
public struct OpenAICompatibleClient: AIClient {
    public let baseURL: URL
    public let model: String
    private let http: HTTPClient

    /// Returns nil when `baseURLString` isn't a usable URL.
    public init?(baseURLString: String, model: String, http: HTTPClient = URLSessionHTTPClient()) {
        guard let url = URL(string: baseURLString.trimmingCharacters(in: .whitespaces)),
              let scheme = url.scheme, scheme == "http" || scheme == "https"
        else { return nil }
        self.baseURL = url
        self.model = model.trimmingCharacters(in: .whitespaces)
        self.http = http
    }

    public func complete(_ request: AIRequest) async throws -> String {
        guard !model.isEmpty else {
            throw AIError.notConfigured("Enter the local model name in the Taalhulp app (Settings → AI helper).")
        }
        let result: (Data, HTTPURLResponse)
        do {
            result = try await http.send(try makeRequest(request))
        } catch let error as URLError {
            let reason = error.code == .timedOut ? "timed out" : "no connection"
            throw AIError.unavailable("Can't reach your local AI server (\(reason)). Is the Mac on and the server running?")
        }
        let (data, response) = result
        guard response.statusCode == 200 else {
            throw AIError.http(status: response.statusCode, message: String(data: data, encoding: .utf8) ?? "")
        }
        return try Self.parse(data)
    }

    func makeRequest(_ request: AIRequest) throws -> URLRequest {
        var system = request.system
        if let schema = request.schema {
            // Local servers don't all support structured output, so ask for the JSON in words.
            system += "\n\nAnswer with only a JSON object (no Markdown, no other text) that follows this JSON Schema:\n\(schema)"
        }
        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": request.prompt],
            ],
            "temperature": 0.2,
            "max_tokens": request.maxTokens,
            "stream": false,
        ]

        var urlRequest = URLRequest(url: baseURL.appendingPathComponent("chat/completions"))
        urlRequest.httpMethod = "POST"
        // Local models on a laptop can be slow, especially the first request after loading.
        urlRequest.timeoutInterval = 120
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)
        return urlRequest
    }

    private struct Response: Decodable {
        struct Choice: Decodable {
            struct Message: Decodable {
                let content: String?
            }
            let message: Message
            let finish_reason: String?
        }
        let choices: [Choice]
    }

    static func parse(_ data: Data) throws -> String {
        guard let response = try? JSONDecoder().decode(Response.self, from: data),
              let choice = response.choices.first
        else { throw AIError.invalidResponse }
        let text = AIJSON.stripThinking(choice.message.content ?? "")
        if text.isEmpty {
            throw choice.finish_reason == "length" ? AIError.truncated : AIError.emptyResponse
        }
        return text
    }
}
