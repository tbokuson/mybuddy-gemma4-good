import XCTest
@testable import MyBuddy

@MainActor
final class ChatResponseServiceTests: XCTestCase {

    private final class PromptCapturingLLMService: LLMServiceProtocol {
        var isLoaded = true
        var isGenerating = false
        var visionLoaded = false
        var backendDescription = "mock"
        var requiresLocalModelAssets = false
        var lastPrompt: String?

        func loadModel() async throws {}

        func generate(prompt: String, maxTokens: Int, samplingProfile: LLMSamplingProfile) async throws -> String {
            lastPrompt = prompt
            return "了解"
        }

        func generateStream(prompt: String, maxTokens: Int, samplingProfile: LLMSamplingProfile) -> AsyncThrowingStream<String, Error> {
            lastPrompt = prompt
            return AsyncThrowingStream { continuation in
                continuation.yield("了解")
                continuation.finish()
            }
        }

        func loadVision() async throws {}
        func unloadVision() {}

        func generateWithImage(prompt: String, imageData: Data, maxTokens: Int, samplingProfile: LLMSamplingProfile) async throws -> String {
            lastPrompt = prompt
            return "了解"
        }
    }

    func testPromptIncludesIdentityTimeAndConversationRules() async throws {
        let llm = PromptCapturingLLMService()
        let service = ChatResponseService(llmService: llm)
        let buddy = BuddyProfile(displayName: "モモ", seed: .appDefault)

        _ = try await service.generateReply(
            for: .init(
                buddy: buddy,
                userNickname: "たろう",
                userTimezone: "Asia/Tokyo",
                turnCount: 3,
                elapsedMinutes: 10,
                memoryContext: "",
                history: [("user", "[13:00] 今日は会議があった")],
                userMessage: "午後はちょっと落ち着いてた"
            )
        )

        let prompt = try XCTUnwrap(llm.lastPrompt)
        XCTAssertTrue(prompt.contains("現在時刻:"))
        XCTAssertTrue(prompt.contains("会話方針:"))
        XCTAssertTrue(prompt.contains("語尾や単語を言い換えて応答する"))
        XCTAssertTrue(prompt.contains("日記・メモ・箇条書き・ト書きを出さず"))
    }

    func testPromptDoesNotAddWrapUpInstructionAtFourTurns() async throws {
        let llm = PromptCapturingLLMService()
        let service = ChatResponseService(llmService: llm)
        let buddy = BuddyProfile(displayName: "モモ", seed: .appDefault)

        _ = try await service.generateReply(
            for: .init(
                buddy: buddy,
                userNickname: "たろう",
                userTimezone: "Asia/Tokyo",
                turnCount: 4,
                elapsedMinutes: 10,
                memoryContext: "",
                history: [("user", "[00:30] 会議のあとラーメン食べた")],
                userMessage: "そのあと帰ってゲームしてた"
            )
        )

        let prompt = try XCTUnwrap(llm.lastPrompt)
        XCTAssertFalse(prompt.contains("締めモード"))
    }

    func testLongUserMessageIsPassedWithoutInjectedControlText() async throws {
        let llm = PromptCapturingLLMService()
        let service = ChatResponseService(llmService: llm)
        let buddy = BuddyProfile(displayName: "モモ", seed: .appDefault)

        _ = try await service.generateReply(
            for: .init(
                buddy: buddy,
                userNickname: "たろう",
                userTimezone: "Asia/Tokyo",
                turnCount: 2,
                elapsedMinutes: 3,
                memoryContext: "",
                history: [],
                userMessage: "午後は打ち合わせが長かったけど、帰り道で少し落ち着いた"
            )
        )

        let prompt = try XCTUnwrap(llm.lastPrompt)
        XCTAssertTrue(prompt.contains("午後は打ち合わせが長かったけど、帰り道で少し落ち着いた"))
        XCTAssertFalse(prompt.contains("これに返答する:"))
    }

    func testSingleAcknowledgmentDoesNotActivateClosingModeAtFiveTurns() async throws {
        let llm = PromptCapturingLLMService()
        let service = ChatResponseService(llmService: llm)
        let buddy = BuddyProfile(displayName: "モモ", seed: .appDefault)

        _ = try await service.generateReply(
            for: .init(
                buddy: buddy,
                userNickname: "たろう",
                userTimezone: "Asia/Tokyo",
                turnCount: 6,
                lowSignalReplyStreak: 1,
                elapsedMinutes: 15,
                memoryContext: "",
                history: [],
                userMessage: "うん"
            )
        )

        let prompt = try XCTUnwrap(llm.lastPrompt)
        XCTAssertFalse(prompt.contains("締めモード"))
        XCTAssertTrue(prompt.contains("「うん」「はい」「そうだね」だけでは会話終了と判断しない"))
    }

    func testRepeatedAcknowledgmentSoftensButDoesNotForceClosingMode() async throws {
        let llm = PromptCapturingLLMService()
        let service = ChatResponseService(llmService: llm)
        let buddy = BuddyProfile(displayName: "モモ", seed: .appDefault)

        _ = try await service.generateReply(
            for: .init(
                buddy: buddy,
                userNickname: "たろう",
                userTimezone: "Asia/Tokyo",
                turnCount: 6,
                lowSignalReplyStreak: 2,
                elapsedMinutes: 15,
                memoryContext: "",
                history: [
                    ("user", "うん"),
                    ("model", "そっか。今日は他に何かあった？")
                ],
                userMessage: "うん"
            )
        )

        let prompt = try XCTUnwrap(llm.lastPrompt)
        XCTAssertFalse(prompt.contains("締めモード"))
        XCTAssertTrue(prompt.contains("短い相づちが続いている"))
        XCTAssertTrue(prompt.contains("勝手に会話終了せず"))
    }

    func testClosingModeActivatesForExplicitEndOfTopicsReply() async throws {
        let llm = PromptCapturingLLMService()
        let service = ChatResponseService(llmService: llm)
        let buddy = BuddyProfile(displayName: "モモ", seed: .appDefault)

        _ = try await service.generateReply(
            for: .init(
                buddy: buddy,
                userNickname: "たろう",
                userTimezone: "Asia/Tokyo",
                turnCount: 3,
                lowSignalReplyStreak: 0,
                elapsedMinutes: 15,
                memoryContext: "",
                history: [],
                userMessage: "もういいかな"
            )
        )

        let prompt = try XCTUnwrap(llm.lastPrompt)
        XCTAssertTrue(prompt.contains("締めモード"))
    }
}
