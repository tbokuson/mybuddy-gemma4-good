import Foundation

enum BuddyAppearanceKind: String, CaseIterable, Identifiable {
    case monster
    case ojisan

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .monster: "モンスター"
        case .ojisan: "おじさん"
        }
    }

    var shortDescription: String {
        switch self {
        case .monster: "やわらかく、親しみやすい"
        case .ojisan: "人っぽく、味がある"
        }
    }

    init(characterType: String) {
        self = BuddyAppearanceKind(rawValue: characterType) ?? .monster
    }
}

enum BuddyAppearanceCandidateFactory {
    static let candidateCount = 3
    private static let dailyChangeKeyPrefix = "buddy.appearance.changed."

    static func makeCandidates(from buddy: BuddyProfile, count: Int = candidateCount) -> [BuddySeed] {
        makeCandidates(from: buddy.seed, count: count)
    }

    static func makeCandidates(
        from buddy: BuddyProfile,
        kind: BuddyAppearanceKind,
        count: Int = candidateCount
    ) -> [BuddySeed] {
        makeCandidates(from: buddy.seed, kind: kind, count: count)
    }

    static func makeCandidates(from seed: BuddySeed, count: Int = candidateCount) -> [BuddySeed] {
        makeCandidates(from: seed, kind: BuddyAppearanceKind(characterType: seed.characterType), count: count)
    }

    static func makeCandidates(
        from seed: BuddySeed,
        kind: BuddyAppearanceKind,
        count: Int = candidateCount
    ) -> [BuddySeed] {
        let safeCount = max(1, count)
        if kind == .ojisan {
            return makeOjisanCandidates(from: seed, count: safeCount)
        }

        return (0..<safeCount).map { _ in
            return BuddySeed.makeRandomMonster(
                personaStyle: seed.personaStyle,
                conversationDistance: seed.conversationDistance,
                memoryPreference: seed.memoryPreference,
                personalityNotes: seed.personalityNotes,
                customTraits: seed.customTraits,
                personaStyleCustom: seed.personaStyleCustom,
                conversationDistanceCustom: seed.conversationDistanceCustom,
                memoryPreferenceCustom: seed.memoryPreferenceCustom,
                roomThemeId: seed.roomThemeId
            )
        }
    }

    private static func makeOjisanCandidates(from seed: BuddySeed, count: Int) -> [BuddySeed] {
        var variants = BuddySeed.ojisanVariants.shuffled()
        var selected: [String] = []

        while selected.count < count {
            if variants.isEmpty {
                variants = BuddySeed.ojisanVariants.shuffled()
            }
            if let variant = variants.popLast() {
                selected.append(variant)
            }
        }

        return selected.map { variant in
            BuddySeed.makeOjisan(
                variant: variant,
                personaStyle: seed.personaStyle,
                conversationDistance: seed.conversationDistance,
                memoryPreference: seed.memoryPreference,
                personalityNotes: seed.personalityNotes,
                customTraits: seed.customTraits,
                personaStyleCustom: seed.personaStyleCustom,
                conversationDistanceCustom: seed.conversationDistanceCustom,
                memoryPreferenceCustom: seed.memoryPreferenceCustom,
                roomThemeId: seed.roomThemeId
            )
        }
    }

    static func applyVisual(from seed: BuddySeed, to buddy: BuddyProfile) {
        buddy.characterType = seed.characterType
        buddy.bodyId = seed.bodyId
        buddy.eyeId = seed.eyeId
        buddy.earId = seed.earId
        buddy.mouthId = seed.mouthId
        buddy.paletteId = seed.paletteId
        buddy.accentIds = seed.accentIds
    }

    static func dailyChangeKey(for date: Date = Date()) -> String {
        let timestamp = Int(DayBoundary.startOfAppDay(for: date).timeIntervalSince1970)
        return "\(dailyChangeKeyPrefix)\(timestamp)"
    }

    static func isDailyChangeKey(_ key: String) -> Bool {
        key.hasPrefix(dailyChangeKeyPrefix)
    }
}
