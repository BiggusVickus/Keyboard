import Foundation

/// Tries several AI servers in order, e.g. Ollama on the PC first and on the Raspberry Pi second.
/// A server that doesn't answer a quick check is skipped; one that fails while answering
/// hands the request to the next one.
public struct FallbackAIClient: AIClient {
    public struct Candidate: Sendable {
        public let name: String
        public let client: AIClient
        /// Nil when the server is up, else why it can't be used (shown when every server fails).
        public let problem: @Sendable () async -> String?

        public init(name: String, client: AIClient, problem: @escaping @Sendable () async -> String?) {
            self.name = name
            self.client = client
            self.problem = problem
        }

        public init(name: String, client: OpenAICompatibleClient) {
            self.init(name: name, client: client, problem: { await client.reachabilityProblem() })
        }
    }

    public let candidates: [Candidate]

    public init(_ candidates: [Candidate]) {
        self.candidates = candidates
    }

    public func complete(_ request: AIRequest) async throws -> String {
        var firstError: Error?
        var skipped: [String] = []
        for candidate in candidates {
            try Task.checkCancellation()
            if let problem = await candidate.problem() {
                skipped.append("\(candidate.name): \(problem)")
                continue
            }
            do {
                return try await candidate.client.complete(request)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // A wrong answer format won't get better elsewhere, but a broken or busy server might.
                if firstError == nil { firstError = error }
            }
        }
        if let firstError { throw firstError }
        throw AIError.unavailable("Can't reach " + (skipped.isEmpty ? "your AI server." : skipped.joined(separator: "\n")))
    }
}
