import XCTest
@testable import KeyboardCore

final class ClaudeClientTests: XCTestCase {
    private let reply = """
        {"id": "msg_1", "type": "message", "role": "assistant", "model": "claude-sonnet-5-5",
         "content": [{"type": "thinking", "thinking": ""}, {"type": "text", "text": "Huis is a het-word."}],
         "stop_reason": "end_turn"}
        """

    func testRequestShape() async throws {
        let http = FakeHTTPClient(json: reply)
        let client = ClaudeClient(apiKey: " sk-ant-test ", model: "claude-sonnet-5-5", http: http)
        let answer = try await client.complete(AIRequest(system: "sys", prompt: "hi", schema: Assistant.translationSchema,
                                                         maxTokens: 123, effort: .medium))
        XCTAssertEqual(answer, "Huis is a het-word.", "thinking blocks are skipped")

        let request = try XCTUnwrap(http.lastRequest)
        XCTAssertEqual(request.url, ClaudeClient.endpoint)
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-api-key"), "sk-ant-test")
        XCTAssertEqual(request.value(forHTTPHeaderField: "anthropic-version"), "2023-06-01")
        XCTAssertEqual(request.value(forHTTPHeaderField: "anthropic-beta"), "server-side-fallback-2026-07-01")

        let body = try XCTUnwrap(http.lastBodyJSON)
        XCTAssertEqual(body["model"] as? String, "claude-sonnet-5-5")
        XCTAssertEqual(body["max_tokens"] as? Int, 123)
        XCTAssertEqual(body["system"] as? String, "sys")
        XCTAssertEqual(body["fallbacks"] as? String, "default")
        XCTAssertNil(body["thinking"], "never send a thinking config; the default is right for every model")
        let output = try XCTUnwrap(body["output_config"] as? [String: Any])
        XCTAssertEqual(output["effort"] as? String, "medium")
        let format = try XCTUnwrap(output["format"] as? [String: Any])
        XCTAssertEqual(format["type"] as? String, "json_schema")
        XCTAssertNotNil(format["schema"] as? [String: Any])
    }

    func testHaikuHasNoServerFallback() async throws {
        let http = FakeHTTPClient(json: reply)
        _ = try await ClaudeClient(apiKey: "k", model: "claude-haiku-5-5", http: http).complete(AIRequest(system: "", prompt: ""))
        XCTAssertNil(http.lastRequest?.value(forHTTPHeaderField: "anthropic-beta"))
        XCTAssertNil(http.lastBodyJSON?["fallbacks"])
    }

    func testOlderCustomModelGetsNoEffort() async throws {
        let http = FakeHTTPClient(json: reply)
        _ = try await ClaudeClient(apiKey: "k", model: "claude-haiku-4-5", http: http).complete(AIRequest(system: "", prompt: ""))
        XCTAssertNil(http.lastBodyJSON?["output_config"])
    }

    func testRefusal() async {
        let http = FakeHTTPClient(json: #"{"content": [], "stop_reason": "refusal"}"#)
        await assertThrows(AIError.refused) {
            _ = try await ClaudeClient(apiKey: "k", model: "claude-opus-5-5", http: http).complete(AIRequest(system: "", prompt: ""))
        }
    }

    func testErrorMessageIsShown() async {
        let http = FakeHTTPClient(status: 400, json: #"{"type": "error", "error": {"type": "invalid_request_error", "message": "model: not found"}}"#)
        await assertThrows(AIError.http(status: 400, message: "model: not found")) {
            _ = try await ClaudeClient(apiKey: "k", model: "claude-nope", http: http).complete(AIRequest(system: "", prompt: ""))
        }
    }

    func testMissingKey() async {
        await assertThrows(AIError.notConfigured("Add your Claude API key in the Taalhulp app (Settings → AI helper).")) {
            _ = try await ClaudeClient(apiKey: "", model: "claude-opus-5-5", http: FakeHTTPClient(json: "")).complete(AIRequest(system: "", prompt: ""))
        }
    }
}

final class LocalClientTests: XCTestCase {
    func testRequestAndThinkingIsStripped() async throws {
        let http = FakeHTTPClient(json: """
            {"choices": [{"message": {"role": "assistant", "content": "<think>hmm</think>\\n{\\"translation\\": \\"Hallo\\", \\"notes\\": \\"\\"}"}, "finish_reason": "stop"}]}
            """)
        let client = try XCTUnwrap(OpenAICompatibleClient(baseURLString: "http://192.168.1.20:11434/v1", model: "qwen3:14b", http: http))
        let translation = try await Assistant(client: client).translate("Hello", from: .english, to: .dutch)
        XCTAssertEqual(translation, Translation(translation: "Hallo", notes: ""))

        XCTAssertEqual(http.lastRequest?.url?.absoluteString, "http://192.168.1.20:11434/v1/chat/completions")
        let body = try XCTUnwrap(http.lastBodyJSON)
        XCTAssertEqual(body["model"] as? String, "qwen3:14b")
        let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
        XCTAssertEqual(messages.first?["role"] as? String, "system")
        XCTAssertTrue((messages.first?["content"] as? String)?.contains("JSON Schema") ?? false)
    }

    func testBadURL() {
        XCTAssertNil(OpenAICompatibleClient(baseURLString: "192.168.1.20", model: "m"))
    }
}

/// An AI that always gives the same answer, for testing `Assistant`.
struct CannedAI: AIClient {
    let answer: String
    func complete(_ request: AIRequest) async throws -> String { answer }
}

final class AssistantTests: XCTestCase {
    func testDecodesReviewWrappedInChatter() async throws {
        let answer = """
            Here you go:
            ```json
            {"is_correct": false, "revised": "Ik woon in de stad.", "summary": "One error: de/het.",
             "changes": [{"original": "het stad", "replacement": "de stad", "explanation": "stad is a de-word.",
                          "optional": false, "topic": "articles"}]}
            ```
            """
        let review = try await Assistant(client: CannedAI(answer: answer))
            .check("Ik woon in het stad.", language: .dutch, level: .errorsOnly)
        XCTAssertFalse(review.isCorrect)
        XCTAssertEqual(review.revised, "Ik woon in de stad.")
        XCTAssertEqual(review.changes.first?.grammarTopic, .articles)
    }

    func testUnknownTopicFallsBackToGrammar() {
        let change = SentenceReview.Change(original: "a", replacement: "b", explanation: "", optional: false, topic: "nonsense")
        XCTAssertEqual(change.grammarTopic, .grammar)
    }

    func testGarbageIsAnError() async {
        await assertThrows(AIError.invalidResponse) {
            _ = try await Assistant(client: CannedAI(answer: "sorry, no")).improve("x", language: .german)
        }
    }

    func testPromptsCarryTheLevelAndText() {
        let check = Assistant.checkRequest("Ich gehe morgen.", language: .german, level: .errorsOnly)
        XCTAssertTrue(check.prompt.contains("<text>Ich gehe morgen.</text>"))
        XCTAssertTrue(check.prompt.contains("Do not suggest optional style changes"))
        XCTAssertNotNil(check.schema)

        let polish = Assistant.checkRequest("x", language: .dutch, level: .polish)
        XCTAssertTrue(polish.prompt.contains("native-sounding"))
    }

    func testSchemasAreValidJSON() throws {
        for schema in [Assistant.reviewSchema, Assistant.translationSchema] {
            XCTAssertNoThrow(try JSONSerialization.jsonObject(with: Data(schema.utf8)))
        }
    }

    func testStripThinking() {
        XCTAssertEqual(AIJSON.stripThinking("<think>a</think> b <think>c</think>"), "b")
        XCTAssertEqual(AIJSON.stripThinking("plain"), "plain")
    }
}

/// `XCTAssertThrowsError` doesn't take async closures.
func assertThrows<E: Error & Equatable>(_ expected: E, file: StaticString = #filePath, line: UInt = #line,
                                        _ body: () async throws -> Void) async {
    do {
        try await body()
        XCTFail("expected \(expected)", file: file, line: line)
    } catch {
        XCTAssertEqual(error as? E, expected, file: file, line: line)
    }
}
