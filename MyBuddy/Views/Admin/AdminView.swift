import SwiftUI
import SwiftData

struct AdminView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var appState: AppState
    @Query private var buddies: [BuddyProfile]
    @Query private var buddyStates: [BuddyState]
    @Query private var users: [UserProfile]
    @Query(sort: \ConversationSession.startedAt, order: .reverse)
    private var sessions: [ConversationSession]
    @Query(sort: \JournalEntry.date, order: .reverse)
    private var journals: [JournalEntry]
    @Query private var diaryNotes: [DiaryNote]
    @Query private var chatMessages: [ChatMessage]

    @State private var showResetConfirm = false
    @State private var showPromptEditor = false
    @AppStorage(AppLanguageMode.storageKey) private var languageModeRawValue = AppLanguageMode.system.rawValue

    private var buddy: BuddyProfile? { buddies.first }
    private var buddyState: BuddyState? { buddyStates.first }
    private var text: AppText {
        AppText(language: (AppLanguageMode(rawValue: languageModeRawValue) ?? .system).resolvedLanguage)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    adminOverviewCard

                    adminSection(text.isEnglish ? "Buddy" : "バディ") {
                        if let buddy {
                            AdminKeyValueRow(label: text.isEnglish ? "Name" : "名前", value: buddy.displayName)
                            AdminKeyValueRow(label: text.buddyProfilePersona, value: text.personaLabel(style: buddy.personaStyle, custom: buddy.personaStyleCustom))
                            AdminKeyValueRow(label: text.buddyProfileDistance, value: text.distanceLabel(distance: buddy.conversationDistance, custom: buddy.conversationDistanceCustom))
                            AdminKeyValueRow(label: text.buddyProfileMemory, value: text.memoryLabel(memory: buddy.memoryPreference, custom: buddy.memoryPreferenceCustom))
                            if !buddy.customTraits.isEmpty {
                                AdminKeyValueRow(label: text.buddyProfileSpecialRule, value: buddy.customTraits)
                            }
                            if !buddy.personalityNotes.isEmpty {
                                AdminKeyValueRow(label: text.isEnglish ? "User memo" : "ユーザーメモ", value: buddy.personalityNotes)
                            }
                        } else {
                            AdminEmptyState(text: text.isEnglish ? "No buddy" : "バディなし")
                        }
                    }

                    adminSection(text.isEnglish ? "Buddy state" : "バディ状態") {
                        if let state = buddyState {
                            AdminKeyValueRow(label: text.isEnglish ? "Streak" : "ストリーク", value: text.streakLabel(days: state.streakDays))
                            AdminKeyValueRow(label: text.isEnglish ? "Intimacy" : "親密度", value: "\(state.intimacyLevel)")
                            AdminKeyValueRow(label: text.isEnglish ? "Last check-in" : "最終チェックイン", value: state.lastCheckInDate?.formatted(.dateTime) ?? (text.isEnglish ? "None" : "なし"))
                        } else {
                            AdminEmptyState(text: text.isEnglish ? "No state data" : "状態データなし")
                        }
                    }

                    adminSection(text.isEnglish ? "Long-term memories" : "長期記憶") {
                        if let state = buddyState, !state.longTermMemories.isEmpty {
                            ForEach(state.longTermMemories.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                                AdminKeyValueRow(label: key, value: value)
                            }
                        } else {
                            AdminEmptyState(text: text.isEnglish ? "No memories" : "記憶なし")
                        }
                    }

                    adminSection(text.isEnglish ? "Recent sessions" : "最近のセッション") {
                        if sessions.isEmpty {
                            AdminEmptyState(text: text.isEnglish ? "No sessions" : "セッションなし")
                        } else {
                            ForEach(sessions.prefix(5)) { session in
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Text(session.type.rawValue)
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(QuietNativeTheme.accent)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 5)
                                            .background(QuietNativeTheme.accentSoft)
                                            .clipShape(Capsule())
                                        Spacer()
                                        Text(text.isEnglish ? "\(session.messageCount) messages" : "\(session.messageCount)メッセージ")
                                            .font(.caption)
                                            .foregroundStyle(QuietNativeTheme.secondaryText)
                                    }

                                    Text(session.startedAt.formatted(.dateTime))
                                        .font(.footnote)
                                        .foregroundStyle(QuietNativeTheme.secondaryText)
                                }
                                .padding(16)
                                .quietNativeCard(cornerRadius: 20, fill: QuietNativeTheme.backgroundWarm)
                            }
                        }
                    }

                    adminSection(text.isEnglish ? "Recent diaries" : "最近の日記") {
                        if journals.isEmpty {
                            AdminEmptyState(text: text.isEnglish ? "No diaries" : "日記なし")
                        } else {
                            ForEach(journals.prefix(5)) { entry in
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(entry.title)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(QuietNativeTheme.primaryText)
                                    Text(entry.formattedDate)
                                        .font(.caption)
                                        .foregroundStyle(QuietNativeTheme.secondaryText)
                                    if !entry.normalizedEmotionTags.isEmpty {
                                        Text(entry.normalizedEmotionTags.joined(separator: ", "))
                                            .font(.caption2)
                                            .foregroundStyle(QuietNativeTheme.accent)
                                    }
                                }
                                .padding(16)
                                .quietNativeCard(cornerRadius: 20, fill: QuietNativeTheme.backgroundWarm)
                            }
                        }
                    }

                    adminSection("LLM") {
                        AdminKeyValueRow(label: text.isEnglish ? "Backend" : "バックエンド", value: appState.llmBackendDescription)
                        AdminKeyValueRow(label: text.isEnglish ? "Status" : "ステータス", value: llmStatusText, tint: llmStatusTint)
                    }

                    adminSection(text.isEnglish ? "Prompt" : "プロンプト") {
                        Button(text.isEnglish ? "Show system prompt" : "システムプロンプトを表示") {
                            showPromptEditor = true
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(QuietNativeTheme.accent)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text(text.isEnglish ? "Danger zone" : "危険な操作")
                            .font(.headline)
                            .foregroundStyle(QuietNativeTheme.primaryText)

                        Button(role: .destructive) {
                            showResetConfirm = true
                        } label: {
                            HStack {
                                Image(systemName: "arrow.counterclockwise")
                                Text(text.isEnglish ? "Reset buddy" : "バディをリセット")
                                Spacer()
                            }
                            .font(.body.weight(.semibold))
                            .padding(16)
                        }
                        .quietNativeCard(cornerRadius: 24, fill: Color.red.opacity(0.08), stroke: Color.red.opacity(0.15))
                        .confirmationDialog(text.resetConfirmTitle, isPresented: $showResetConfirm, titleVisibility: .visible) {
                            Button(text.resetConfirmAction, role: .destructive) {
                                resetAllData()
                            }
                            Button(text.cancel, role: .cancel) {}
                        } message: {
                            Text(text.resetMessage)
                        }

                        Text(text.isEnglish ? "Deletes all data and returns to onboarding." : "全データを削除してオンボーディングに戻ります")
                            .font(.caption)
                            .foregroundStyle(QuietNativeTheme.secondaryText)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 32)
            }
            .quietNativeTabBarClearance()
            .scrollIndicators(.hidden)
            .background(QuietNativeTheme.pageGradient.ignoresSafeArea())
            .navigationTitle(text.adminTab)
            .sheet(isPresented: $showPromptEditor) {
                PromptEditorView(buddy: buddy)
            }
        }
    }

    private var adminOverviewCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(text.isEnglish ? "Internal status" : "内部ステータス")
                .font(.caption)
                .foregroundStyle(QuietNativeTheme.secondaryText)

            Text(text.isEnglish ? "Check local data status" : "ローカルデータの状態を確認できます")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(QuietNativeTheme.primaryText)

            HStack(spacing: 10) {
                OverviewPill(label: text.isEnglish ? "Chats" : "会話", value: "\(sessions.count)")
                OverviewPill(label: text.isEnglish ? "Diaries" : "日記", value: "\(journals.count)")
                OverviewPill(label: text.isEnglish ? "Memories" : "記憶", value: buddyState.map { "\($0.longTermMemories.count)" } ?? "0")
            }
        }
        .padding(22)
        .background(QuietNativeTheme.heroGradient)
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.white.opacity(0.6), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    @ViewBuilder
    private func adminSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
                .foregroundStyle(QuietNativeTheme.primaryText)

            VStack(spacing: 10) {
                content()
            }
        }
    }

    private var llmStatusText: String {
        switch appState.llmStatus {
        case .notLoaded: text.isEnglish ? "Not loaded" : "未ロード"
        case .loading: text.loading
        case .loaded: text.isEnglish ? "Ready" : "準備完了"
        case .error(let msg): msg
        }
    }

    private var llmStatusTint: Color {
        switch appState.llmStatus {
        case .notLoaded: QuietNativeTheme.secondaryText
        case .loading: QuietNativeTheme.accent
        case .loaded: .green
        case .error: .red
        }
    }

    private func resetAllData() {
        for item in chatMessages { modelContext.delete(item) }
        for item in diaryNotes { modelContext.delete(item) }
        for item in buddies { modelContext.delete(item) }
        for item in buddyStates { modelContext.delete(item) }
        for item in sessions { modelContext.delete(item) }
        for item in journals { modelContext.delete(item) }
        for item in users { modelContext.delete(item) }

        let defaults = UserDefaults.standard
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix("home.todayJournalCreated.") {
            defaults.removeObject(forKey: key)
        }
        for key in defaults.dictionaryRepresentation().keys where BuddyAppearanceCandidateFactory.isDailyChangeKey(key) {
            defaults.removeObject(forKey: key)
        }

        try? modelContext.save()
        appState.preserveModelSetupAfterUserDataReset()
    }
}

private struct OverviewPill: View {
    let label: String
    let value: String

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.headline.weight(.bold))
                .foregroundStyle(QuietNativeTheme.primaryText)
            Text(label)
                .font(.caption)
                .foregroundStyle(QuietNativeTheme.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .quietNativeCard(cornerRadius: 18, fill: Color.white.opacity(0.55), stroke: Color.white.opacity(0.4))
    }
}

private struct AdminKeyValueRow: View {
    let label: String
    let value: String
    var tint: Color = QuietNativeTheme.primaryText

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(label)
                .font(.caption)
                .foregroundStyle(QuietNativeTheme.secondaryText)
                .frame(width: 76, alignment: .leading)
            Text(value)
                .font(.footnote)
                .foregroundStyle(tint)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .quietNativeCard(cornerRadius: 20)
    }
}

private struct AdminEmptyState: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(QuietNativeTheme.secondaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .quietNativeCard(cornerRadius: 20, fill: QuietNativeTheme.backgroundWarm)
    }
}

// MARK: - Prompt Editor

struct PromptEditorView: View {
    let buddy: BuddyProfile?
    @Environment(\.dismiss) private var dismiss
    @AppStorage(AppLanguageMode.storageKey) private var languageModeRawValue = AppLanguageMode.system.rawValue

    private var text: AppText {
        AppText(language: (AppLanguageMode(rawValue: languageModeRawValue) ?? .system).resolvedLanguage)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                if let buddy {
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(text.isEnglish ? "System prompt" : "システムプロンプト")
                                .font(.headline)
                                .foregroundStyle(QuietNativeTheme.primaryText)

                            Text(buddy.systemPrompt)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(QuietNativeTheme.primaryText)
                                .padding(16)
                                .quietNativeCard(cornerRadius: 20, fill: QuietNativeTheme.backgroundWarm)
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text(text.isEnglish ? "Memory context" : "記憶コンテキスト")
                                .font(.headline)
                                .foregroundStyle(QuietNativeTheme.primaryText)

                            Text(text.isEnglish
                                 ? "This is built dynamically by MemoryContextBuilder and can only be inspected when a chat starts."
                                 : "MemoryContextBuilder で動的に構築されるため、チャット開始時にのみ確認可能です。")
                                .font(.caption)
                                .foregroundStyle(QuietNativeTheme.secondaryText)
                                .padding(16)
                                .quietNativeCard(cornerRadius: 20)
                        }
                    }
                    .padding(20)
                } else {
                    Text(text.isEnglish ? "Buddy does not exist" : "バディが存在しません")
                        .foregroundStyle(QuietNativeTheme.secondaryText)
                        .padding()
                }
            }
            .background(QuietNativeTheme.pageGradient.ignoresSafeArea())
            .navigationTitle(text.isEnglish ? "Prompt" : "プロンプト")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(text.close) { dismiss() }
                        .foregroundStyle(QuietNativeTheme.accent)
                }
            }
        }
    }
}
