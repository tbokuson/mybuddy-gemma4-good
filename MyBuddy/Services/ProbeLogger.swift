import Foundation

enum ProbeChannel {
    nonisolated static let llm = "probe.llm"
    nonisolated static let onboarding = "probe.onboarding"
    nonisolated static let chat = "probe.chat"
    nonisolated static let diary = "probe.diary"
}

enum ProbeLogger {
    #if DEBUG
    nonisolated static let isEnabled = true
    #else
    nonisolated static let isEnabled = false
    #endif

    nonisolated static func log(_ channel: String, _ message: @autoclosure () -> String) {
        guard isEnabled else { return }
        print("[\(channel)] \(message())")
    }

    nonisolated static func block(_ channel: String, title: String, text: String) {
        guard isEnabled else { return }

        print("[\(channel)] \(title) BEGIN")

        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        let lines = normalized.split(separator: "\n", omittingEmptySubsequences: false)

        if lines.isEmpty {
            print("[\(channel)] | <empty>")
        } else {
            for line in lines {
                print("[\(channel)] | \(line)")
            }
        }

        print("[\(channel)] \(title) END")
    }

    nonisolated static func inline(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\r\n", with: "\\n")
            .replacingOccurrences(of: "\n", with: "\\n")
    }

    nonisolated static func samplingSummary(profile: LLMSamplingProfile, maxTokens: Int) -> String {
        let seed = profile.seed.map(String.init) ?? "random"
        return "profile=\(profile.label) temp=\(profile.temperature) top_k=\(profile.topK) top_p=\(profile.topP) min_p=\(profile.minP) repeat_penalty=\(profile.repeatPenalty) repeat_last_n=\(profile.repeatLastN) seed=\(seed) max_tokens=\(maxTokens)"
    }
}
