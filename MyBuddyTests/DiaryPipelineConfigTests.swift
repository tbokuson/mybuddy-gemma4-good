import XCTest
@testable import MyBuddy

@MainActor
final class DiaryPipelineConfigTests: XCTestCase {

    func testDefaultMinTurnsToCompileIsWithinSensibleRange() {
        let config = DiaryPipelineConfig.default
        XCTAssertGreaterThanOrEqual(config.minTurnsToCompile, 1)
        XCTAssertLessThanOrEqual(config.minTurnsToCompile, 10)
    }

    func testDefaultQualityGuardRatiosAreInUnitInterval() {
        let config = DiaryPipelineConfig.default
        XCTAssertGreaterThan(config.qualityGuardRatio, 0)
        XCTAssertLessThanOrEqual(config.qualityGuardRatio, 1.0)
        XCTAssertGreaterThan(config.nameCoverageThreshold, 0)
        XCTAssertLessThanOrEqual(config.nameCoverageThreshold, 1.0)
        XCTAssertGreaterThan(config.factCoverageThreshold, 0)
        XCTAssertLessThanOrEqual(config.factCoverageThreshold, 1.0)
    }

    func testDefaultMaxRetriesIsNonNegative() {
        let config = DiaryPipelineConfig.default
        XCTAssertGreaterThanOrEqual(config.maxRetries, 0)
    }

    func testThinkingStageUsesJournalProfile() {
        let config = DiaryPipelineConfig.default
        XCTAssertEqual(config.thinkingStage.samplingProfile, .journal)
        XCTAssertGreaterThanOrEqual(config.thinkingStage.maxTokens, 512)
        XCTAssertLessThanOrEqual(config.thinkingStage.maxTokens, 4096)
    }

    func testCanCompileRespectsMinTurns() {
        let config = DiaryPipelineConfig.default
        XCTAssertFalse(config.canCompile(turnCount: 0))
        XCTAssertFalse(config.canCompile(turnCount: config.minTurnsToCompile - 1))
        XCTAssertTrue(config.canCompile(turnCount: config.minTurnsToCompile))
        XCTAssertTrue(config.canCompile(turnCount: config.minTurnsToCompile + 10))
    }
}
