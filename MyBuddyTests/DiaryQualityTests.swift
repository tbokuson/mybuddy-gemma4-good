import XCTest
@testable import MyBuddy

/// 日記生成の E2E 品質テスト。
///
/// Ollama 経由で `DiaryPipeline.run(input:)` を各 fixture に対して実行し、
/// `DiaryQualityMetrics` で計算された指標が fixture の threshold を満たすことを検証する。
///
/// ローカル Ollama が起動していない場合は `XCTSkip` する (CI 等ではスキップ、ローカル開発時のみ走る)。
/// 実行方法: `make test-diary-quality` または Xcode から直接。
///
/// 合否ラインは fixture 側 (`MyBuddyTests/Fixtures/conversations/*.json`) の thresholds に集約。
@MainActor
final class DiaryQualityTests: XCTestCase {
    private static let runFlagKey = "MYBUDDY_RUN_OLLAMA_TESTS"
    private static let reachabilityTimeout: TimeInterval = 1.5

    // MARK: - Ollama gating

    private func requireOllamaOrSkip() async throws -> OllamaService {
        guard Self.isEnabledForLocalRun else {
            throw XCTSkip("Ollama 実LLMテストは明示的に有効化した場合のみ実行します")
        }

        let configuration = AppEnvironment.ollamaConfiguration

        guard try await isOllamaReachable(at: configuration.baseURL) else {
            throw XCTSkip("ローカル Ollama (\(configuration.baseURL)) に接続できないためスキップします")
        }

        let service = OllamaService(configuration: configuration)
        try await service.loadModel()
        return service
    }

    private func isOllamaReachable(at baseURL: URL) async throws -> Bool {
        let url = baseURL.appending(path: "/api/tags")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = Self.reachabilityTimeout
        configuration.timeoutIntervalForResource = Self.reachabilityTimeout
        configuration.waitsForConnectivity = false
        let session = URLSession(configuration: configuration)
        let (_, response) = try await session.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse else { return false }
        return (200..<300).contains(httpResponse.statusCode)
    }

    private static var isEnabledForLocalRun: Bool {
        ProcessInfo.processInfo.environment[runFlagKey] == "1"
    }

    // MARK: - Test runner

    private func runFixture(named name: String) async throws {
        let service = try await requireOllamaOrSkip()
        let fixture = try DiaryQualityFixture.load(named: name)
        let pipeline = DiaryPipeline(llmService: service, config: .default)
        let input = fixture.makePipelineInput()

        let result = try await pipeline.run(input: input)

        // 採用されない場合は E2E としては失敗扱い (新規日記なので accepted=true が期待値)
        XCTAssertTrue(
            result.accepted,
            "[\(fixture.id)] Stage 5 に拒否された: \(result.rejectionReason ?? "unknown")"
        )

        let report = DiaryQualityMetrics.evaluate(result: result, fixture: fixture)

        // ベースライン書き出し: 環境変数 MYBUDDY_WRITE_BASELINE=1 または `/tmp/mybuddy-write-baseline`
        // フラグファイルが存在する場合に有効化する。
        // iOS シミュレータのテストランナは xcodebuild からの env var を直接受け取れないため、
        // フラグファイル方式も併用する (シェルから `touch /tmp/mybuddy-write-baseline` で ON にできる)。
        let baselineEnvOn = ProcessInfo.processInfo.environment["MYBUDDY_WRITE_BASELINE"] == "1"
        let baselineFlagOn = FileManager.default.fileExists(atPath: "/tmp/mybuddy-write-baseline")
        if baselineEnvOn || baselineFlagOn {
            BaselineWriter.shared.record(
                fixtureId: fixture.id,
                result: result,
                report: report
            )
        }

        // 可読性のため、失敗時に詳細を出す
        if !report.passes(thresholds: fixture.thresholds) {
            let detail = """

            === [\(fixture.id)] 品質ライン未達 ===
            本文 (\(report.bodyLength) 文字):
            \(result.body)

            nameCoverage = \(report.nameCoverage) (threshold=\(fixture.thresholds.nameCoverage))
              欠落固有名詞: \(report.missingProperNouns)
            factCoverage = \(report.factCoverage) (threshold=\(fixture.thresholds.factCoverage))
              欠落事実: \(report.missingFacts)
            emotionMatchCount = \(report.emotionMatchCount) (threshold=\(fixture.thresholds.minEmotionMatches))
              一致カテゴリ: \(report.matchedEmotionCategories)
              全タグ: \(result.emotionTags)
            lengthOK = \(report.lengthOK) (bounds=[\(fixture.lengthBounds.minCharacters), \(fixture.lengthBounds.maxCharacters)])
            """
            XCTFail(detail)
        }
    }

    // MARK: - Fixture cases

    func testShortMinimalFixture() async throws {
        try await runFixture(named: "short-minimal")
    }

    func testNormalTypicalFixture() async throws {
        try await runFixture(named: "normal-typical")
    }

    func testLongMultiTopicFixture() async throws {
        try await runFixture(named: "long-multi-topic")
    }

    func testNameHeavyFixture() async throws {
        try await runFixture(named: "name-heavy")
    }

    func testMixedEmotionFixture() async throws {
        try await runFixture(named: "mixed-emotion")
    }
}
