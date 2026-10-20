import XCTest
@testable import KeyboardCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Returns a canned response and remembers the request.
final class FakeHTTPClient: HTTPClient, @unchecked Sendable {
    var status = 200
    var body = Data()
    private(set) var lastRequest: URLRequest?

    init(status: Int = 200, json: String) {
        self.status = status
        self.body = Data(json.utf8)
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        lastRequest = request
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        return (body, response)
    }

    var lastBodyJSON: [String: Any]? {
        guard let data = lastRequest?.httpBody else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    var lastBodyString: String {
        lastRequest?.httpBody.flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }
}

final class LanguageToolTests: XCTestCase {
    static let sampleText = "Ik woon in het stad. Dat is erg leuk."
    static let sampleResponse = """
        {"matches": [
          {"message": "Bedoelt u 'de stad'? 'stad' is een de-woord.", "shortMessage": "Lidwoord",
           "replacements": [{"value": "de stad"}], "offset": 11, "length": 8,
           "sentence": "Ik woon in het stad.",
           "rule": {"id": "NL_ARTICLE_TEST", "issueType": "grammar", "category": {"id": "GRAMMAR"}}},
          {"message": "Dit woord kan vaak weg.", "replacements": [{"value": "is leuk"}],
           "offset": 25, "length": 11,
           "rule": {"id": "NL_REDUNDANT_TEST", "issueType": "style", "category": {"id": "REDUNDANCY"}}},
          {"message": "Out of range", "replacements": [], "offset": 500, "length": 3,
           "rule": {"id": "BROKEN"}}
        ]}
        """

    func testParsesMatches() throws {
        let issues = try LanguageToolClient.parse(Data(Self.sampleResponse.utf8), text: Self.sampleText,
                                                  language: .dutch, level: .errorsAndImprovements)
        XCTAssertEqual(issues.count, 2, "the out-of-range match is dropped")
        XCTAssertEqual(issues[0].text, "het stad")
        XCTAssertEqual(issues[0].replacements, ["de stad"])
        XCTAssertEqual(issues[0].kind, .error)
        XCTAssertEqual(issues[0].topic, .articles, "from the Dutch word 'de-woord' in the message")
        XCTAssertEqual(issues[1].kind, .tip)
        XCTAssertEqual(issues[1].topic, .style)
    }

    func testErrorsOnlyDropsTips() throws {
        let issues = try LanguageToolClient.parse(Data(Self.sampleResponse.utf8), text: Self.sampleText,
                                                  language: .dutch, level: .errorsOnly)
        XCTAssertEqual(issues.map(\.kind), [.error])
    }

    func testRequestIsFormEncoded() async throws {
        let http = FakeHTTPClient(json: #"{"matches": []}"#)
        let client = try XCTUnwrap(LanguageToolClient(urlString: "https://api.languagetool.org/v2/check", http: http))
        _ = try await client.check("Één & twee", language: .dutch, level: .polish)

        let body = http.lastBodyString
        XCTAssertTrue(body.contains("text=%C3%89%C3%A9n%20%26%20twee"), body)
        XCTAssertTrue(body.contains("language=nl"))
        XCTAssertTrue(body.contains("motherTongue=en-US"))
        XCTAssertTrue(body.contains("level=picky"))
        XCTAssertEqual(http.lastRequest?.httpMethod, "POST")
    }

    func testRateLimit() async throws {
        let http = FakeHTTPClient(status: 429, json: "")
        let client = try XCTUnwrap(LanguageToolClient(urlString: "https://example.com/v2/check", http: http))
        do {
            _ = try await client.check("Hoi", language: .dutch, level: .errorsOnly)
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? GrammarCheckError, .rateLimited)
        }
    }

    func testInvalidURL() {
        XCTAssertNil(LanguageToolClient(urlString: "not a url"))
        XCTAssertNil(LanguageToolClient(urlString: "ftp://example.com"))
    }

    func testTopicClassification() {
        XCTAssertEqual(GrammarTopic.classify(ruleID: "GERMAN_SPELLER_RULE", categoryID: "TYPOS", issueType: "misspelling",
                                             message: "", language: .german), .spelling)
        XCTAssertEqual(GrammarTopic.classify(ruleID: "X", categoryID: nil, issueType: "grammar",
                                             message: "Möglicherweise fehlende Übereinstimmung des Kasus", language: .german), .cases)
        XCTAssertEqual(GrammarTopic.classify(ruleID: "X", categoryID: nil, issueType: "grammar",
                                             message: "Bitte verbessern Sie den Satz", language: .german), .grammar,
                       "'verbessern' must not count as 'Verb'")
        XCTAssertEqual(GrammarTopic.classify(ruleID: "X", categoryID: "CASING", issueType: nil,
                                             message: "", language: .dutch), .capitalization)
    }

    func testEveryTopicHasTextForEveryLanguage() {
        for topic in GrammarTopic.allCases {
            for language in KeyboardLanguage.allCases {
                XCTAssertFalse(topic.title(for: language).isEmpty)
                XCTAssertFalse(topic.explanation(for: language).isEmpty)
            }
        }
    }
}

final class GrammarResultTests: XCTestCase {
    private func issue(_ text: String, at location: Int, rule: String = "R") -> GrammarIssue {
        GrammarIssue(range: UTF16Range(location: location, length: text.utf16.count), text: text,
                     message: "", replacements: [], ruleID: rule, kind: .error, source: .languageTool,
                     topic: .grammar, sentence: "")
    }

    func testLiveIssuesFollowTheText() {
        let result = GrammarResult(text: "Het auto is mooi. ", language: .dutch,
                                   issues: [issue("Het auto", at: 0), issue("mooi", at: 12)])
        XCTAssertEqual(result.liveIssues(in: "Het auto is mooi. En").count, 2)
        // The user changed the first words: that issue no longer fits.
        XCTAssertEqual(result.liveIssues(in: "De auto is mooi. ").map(\.text), [])
    }

    func testHidesIssueOnWordBeingTyped() {
        let result = GrammarResult(text: "Ik ben thui", language: .dutch, issues: [issue("thui", at: 7)])
        XCTAssertTrue(result.liveIssues(in: "Ik ben thui").isEmpty)
        XCTAssertEqual(result.liveIssues(in: "Ik ben thui ").count, 1)
    }

    func testIgnoredIssuesAreHidden() {
        let flagged = issue("mooi", at: 0, rule: "STYLE")
        let result = GrammarResult(text: "mooi ", language: .dutch, issues: [flagged])
        XCTAssertTrue(result.liveIssues(in: "mooi ", ignoring: [flagged.ignoreKey]).isEmpty)
    }

    func testMergePrefersLocalIssues() {
        let local = GrammarIssue(range: UTF16Range(location: 0, length: 8), text: "het auto", message: "",
                                 replacements: ["de auto"], ruleID: "TAALHULP_DE_HET", kind: .error,
                                 source: .articles, topic: .articles, sentence: "")
        let merged = GrammarChecker.merge(local: [local], remote: [issue("het auto", at: 0), issue("rood", at: 12)])
        XCTAssertEqual(merged.map(\.source), [.articles, .languageTool])
    }

    func testCheckerRunsOfflineForDutch() async {
        let result = await GrammarChecker().check("Ik zie het auto. ", language: .dutch, level: .errorsOnly,
                                                  servers: [])
        XCTAssertEqual(result.issues.first?.replacements, ["de auto"])
        XCTAssertNil(result.warning)
    }
}

/// Answers per host: a status code, or a network error when the host is "down".
final class RoutingHTTPClient: HTTPClient, @unchecked Sendable {
    var statusByHost: [String: Int] = [:]
    var downHosts: Set<String> = []
    private(set) var hostsAsked: [String] = []

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let host = request.url!.host!
        hostsAsked.append(host)
        if downHosts.contains(host) { throw URLError(.timedOut) }
        let status = statusByHost[host] ?? 200
        let body = Data(#"{"matches": [{"message": "m", "replacements": [], "offset": 0, "length": 2, "rule": {"id": "R", "issueType": "grammar"}}]}"#.utf8)
        return (body, HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
}

final class LanguageToolBackupTests: XCTestCase {
    private func settings(own: String) -> TaalhulpSettings {
        var settings = TaalhulpSettings()
        settings.languageToolURL = own
        return settings
    }

    func testOwnServerFirstThenPublic() {
        let servers = LanguageToolClient.servers(for: settings(own: "http://192.168.1.20:8010/v2/check"))
        XCTAssertEqual(servers.map { $0.endpoint.host }, ["192.168.1.20", "api.languagetool.org"])
        XCTAssertEqual(servers.first?.timeout, 3, "your server gets a short timeout")
    }

    func testNoOwnServerUsesPublicOnly() {
        XCTAssertEqual(LanguageToolClient.servers(for: settings(own: "")).map { $0.endpoint.host },
                       ["api.languagetool.org"])
        XCTAssertEqual(LanguageToolClient.servers(for: settings(own: "not a url")).map { $0.endpoint.host },
                       ["api.languagetool.org"])
        XCTAssertEqual(LanguageToolClient.servers(for: settings(own: TaalhulpSettings.publicLanguageToolURL)).count, 1,
                       "the public server isn't asked twice")
    }

    func testOldSavedPublicURLBecomesEmpty() throws {
        let json = #"{"languageToolURL":"https://api.languagetool.org/v2/check"}"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(TaalhulpSettings.self, from: json)
        XCTAssertEqual(decoded.languageToolURL, "")
        XCTAssertNil(decoded.ownLanguageToolURL)
    }

    func testFallsBackWhenOwnServerIsDown() async {
        let http = RoutingHTTPClient()
        http.downHosts = ["192.168.1.20"]
        let servers = LanguageToolClient.servers(for: settings(own: "http://192.168.1.20:8010/v2/check"), http: http)
        let result = await GrammarChecker().check("Hi there", language: .english, level: .errorsOnly, servers: servers)
        XCTAssertEqual(http.hostsAsked, ["192.168.1.20", "api.languagetool.org"])
        XCTAssertNil(result.warning, "the backup answered, so no warning")
        XCTAssertEqual(result.issues.count, 1)
    }

    func testOwnServerWorkingSkipsBackup() async {
        let http = RoutingHTTPClient()
        let servers = LanguageToolClient.servers(for: settings(own: "http://192.168.1.20:8010/v2/check"), http: http)
        _ = await GrammarChecker().check("Hi there", language: .english, level: .errorsOnly, servers: servers)
        XCTAssertEqual(http.hostsAsked, ["192.168.1.20"])
    }

    func testWarningOnlyWhenBothFail() async {
        let http = RoutingHTTPClient()
        http.downHosts = ["192.168.1.20"]
        http.statusByHost = ["api.languagetool.org": 429]
        let servers = LanguageToolClient.servers(for: settings(own: "http://192.168.1.20:8010/v2/check"), http: http)
        let result = await GrammarChecker().check("Hi there", language: .english, level: .errorsOnly, servers: servers)
        XCTAssertEqual(result.warning, GrammarCheckError.rateLimited.message)
    }
}
