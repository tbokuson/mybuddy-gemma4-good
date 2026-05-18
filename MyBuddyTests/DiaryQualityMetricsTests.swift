import XCTest
@testable import MyBuddy

/// `DiaryQualityMetrics` の純粋関数が正しい指標を計算することを保証するテスト。
///
/// LLM を呼ばないため、Ollama なしで高速に走る。
/// これで評価ロジックが壊れていないことを確認してから `DiaryQualityTests` を実行する想定。
@MainActor
final class DiaryQualityMetricsTests: XCTestCase {

    // MARK: - Fixtures

    private func makeFixture(
        expectedProperNouns: [String] = [],
        expectedFacts: [String] = [],
        expectedEmotionCategories: [String] = [],
        lengthMin: Int = 0,
        lengthMax: Int = 10_000,
        nameCoverageThreshold: Double = 0.5,
        factCoverageThreshold: Double = 0.5,
        minEmotionMatches: Int = 1
    ) -> DiaryQualityFixture {
        DiaryQualityFixture(
            id: "test",
            description: "unit-test fixture",
            memoryPreference: "balanced",
            buddyName: "",
            messages: [],
            notes: [],
            expectedProperNouns: expectedProperNouns,
            expectedFacts: expectedFacts,
            expectedEmotionCategories: expectedEmotionCategories,
            lengthBounds: DiaryQualityFixture.LengthBounds(
                minCharacters: lengthMin,
                maxCharacters: lengthMax
            ),
            thresholds: DiaryQualityFixture.Thresholds(
                nameCoverage: nameCoverageThreshold,
                factCoverage: factCoverageThreshold,
                minEmotionMatches: minEmotionMatches
            )
        )
    }

    private func makeResult(
        body: String,
        emotionTags: [String] = []
    ) -> DiaryPipelineResult {
        DiaryPipelineResult(
            extractedMemos: [],
            body: body,
            title: "タイトル",
            emotionTags: emotionTags,
            tomorrowNote: "",
            nameCoverage: 1.0,
            accepted: true,
            rejectionReason: nil
        )
    }

    // MARK: - nameCoverage

    func testNameCoverageIsOneWhenAllNounsPresent() {
        let fixture = makeFixture(expectedProperNouns: ["横浜", "ジョイポリス"])
        let result = makeResult(body: "今日は横浜のジョイポリスに行った")
        let report = DiaryQualityMetrics.evaluate(result: result, fixture: fixture)
        XCTAssertEqual(report.nameCoverage, 1.0, accuracy: 0.0001)
        XCTAssertTrue(report.missingProperNouns.isEmpty)
    }

    func testNameCoverageIsPartialWhenSomeNounsMissing() {
        let fixture = makeFixture(expectedProperNouns: ["横浜", "ジョイポリス", "中華街"])
        let result = makeResult(body: "今日は横浜のジョイポリスに行った")
        let report = DiaryQualityMetrics.evaluate(result: result, fixture: fixture)
        XCTAssertEqual(report.nameCoverage, 2.0 / 3.0, accuracy: 0.0001)
        XCTAssertEqual(report.missingProperNouns, ["中華街"])
    }

    func testNameCoverageIsOneWhenExpectedNounsEmpty() {
        let fixture = makeFixture(expectedProperNouns: [])
        let result = makeResult(body: "何もない本文")
        let report = DiaryQualityMetrics.evaluate(result: result, fixture: fixture)
        XCTAssertEqual(report.nameCoverage, 1.0, accuracy: 0.0001)
    }

    // MARK: - factCoverage

    func testFactCoverageIsOneWhenAllFactsPresent() {
        let fixture = makeFixture(expectedFacts: ["ラーメン", "打ち合わせ"])
        let result = makeResult(body: "午前は打ち合わせがあって、お昼はラーメンを食べた")
        let report = DiaryQualityMetrics.evaluate(result: result, fixture: fixture)
        XCTAssertEqual(report.factCoverage, 1.0, accuracy: 0.0001)
    }

    func testFactCoverageReportsMissing() {
        let fixture = makeFixture(expectedFacts: ["ラーメン", "打ち合わせ", "ジム"])
        let result = makeResult(body: "午前は打ち合わせ。お昼はラーメン")
        let report = DiaryQualityMetrics.evaluate(result: result, fixture: fixture)
        XCTAssertEqual(report.missingFacts, ["ジム"])
        XCTAssertEqual(report.factCoverage, 2.0 / 3.0, accuracy: 0.0001)
    }

    // MARK: - emotionMatchCount

    func testEmotionExactMatch() {
        let fixture = makeFixture(expectedEmotionCategories: ["嬉しい", "疲れ"])
        let result = makeResult(body: "本文", emotionTags: ["嬉しい", "疲れ"])
        let report = DiaryQualityMetrics.evaluate(result: result, fixture: fixture)
        XCTAssertEqual(report.emotionMatchCount, 2)
    }

    func testEmotionSynonymMatch() {
        // 「幸せ」が期待カテゴリで、タグが「しあわせ」でも一致する
        let fixture = makeFixture(expectedEmotionCategories: ["幸せ"])
        let result = makeResult(body: "本文", emotionTags: ["しあわせ"])
        let report = DiaryQualityMetrics.evaluate(result: result, fixture: fixture)
        XCTAssertEqual(report.emotionMatchCount, 1)
    }

    func testEmotionNoMatch() {
        let fixture = makeFixture(expectedEmotionCategories: ["嬉しい"])
        let result = makeResult(body: "本文", emotionTags: ["不安", "怒り"])
        let report = DiaryQualityMetrics.evaluate(result: result, fixture: fixture)
        XCTAssertEqual(report.emotionMatchCount, 0)
    }

    // MARK: - length bounds

    func testLengthOKWhenWithinBounds() {
        let fixture = makeFixture(lengthMin: 5, lengthMax: 20)
        let result = makeResult(body: "十文字の本文です")
        let report = DiaryQualityMetrics.evaluate(result: result, fixture: fixture)
        XCTAssertTrue(report.lengthOK)
    }

    func testLengthFailsWhenTooShort() {
        let fixture = makeFixture(lengthMin: 100, lengthMax: 500)
        let result = makeResult(body: "短い")
        let report = DiaryQualityMetrics.evaluate(result: result, fixture: fixture)
        XCTAssertFalse(report.lengthOK)
    }

    func testLengthFailsWhenTooLong() {
        let fixture = makeFixture(lengthMin: 1, lengthMax: 5)
        let result = makeResult(body: "長すぎる本文だよね")
        let report = DiaryQualityMetrics.evaluate(result: result, fixture: fixture)
        XCTAssertFalse(report.lengthOK)
    }

    // MARK: - passes(thresholds:)

    func testPassesReturnsTrueWhenAllMetricsMet() {
        let fixture = makeFixture(
            expectedProperNouns: ["横浜"],
            expectedFacts: ["ラーメン"],
            expectedEmotionCategories: ["楽しい"],
            lengthMin: 5,
            lengthMax: 100,
            nameCoverageThreshold: 1.0,
            factCoverageThreshold: 1.0,
            minEmotionMatches: 1
        )
        let result = makeResult(
            body: "今日は横浜でラーメンを食べた",
            emotionTags: ["楽しい"]
        )
        let report = DiaryQualityMetrics.evaluate(result: result, fixture: fixture)
        XCTAssertTrue(report.passes(thresholds: fixture.thresholds))
    }

    func testPassesReturnsFalseWhenNameCoverageBelowThreshold() {
        let fixture = makeFixture(
            expectedProperNouns: ["横浜", "中華街"],
            nameCoverageThreshold: 1.0,
            factCoverageThreshold: 0.0,
            minEmotionMatches: 0
        )
        let result = makeResult(body: "今日は横浜に行った")
        let report = DiaryQualityMetrics.evaluate(result: result, fixture: fixture)
        XCTAssertFalse(report.passes(thresholds: fixture.thresholds))
    }
}
