import SwiftUI
import SwiftData

struct HomeView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.modelContext) private var modelContext
    @Query private var buddies: [BuddyProfile]
    @Query private var buddyStates: [BuddyState]
    @Query(sort: \JournalEntry.date, order: .reverse)
    private var journals: [JournalEntry]
    @AppStorage(AppLanguageMode.storageKey)
    private var appLanguageRawValue = AppLanguageMode.system.rawValue

    @State private var showChat = false
    @State private var hasTodayJournalBadge = false
    @State private var hasTodaySession = false

    private var buddy: BuddyProfile? { buddies.first }
    private var state: BuddyState? { buddyStates.first }
    private var heroSeed: BuddySeed { buddy?.seed ?? .makeDefault() }
    private var text: AppText {
        let mode = AppLanguageMode(rawValue: appLanguageRawValue) ?? .system
        return AppText(language: mode.resolvedLanguage)
    }

    private var buttonLabel: String {
        switch appState.llmStatus {
        case .loading: return text.loading
        case .error: return text.aiLoadError
        default: return hasTodaySession ? text.continueConversation : text.startConversation
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    CompanionHeroCard(
                        buddy: buddy,
                        seed: heroSeed,
                        state: state,
                        buttonLabel: buttonLabel,
                        subtitle: heroSubtitle,
                        isReady: appState.isLLMReady,
                        hasTodayJournalBadge: hasTodayJournalBadge,
                        onStartChat: { showChat = true }
                    )

                    if let statusMessage {
                        statusCard(message: statusMessage.text, tint: statusMessage.tint, icon: statusMessage.icon)
                    }

                    if !journals.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(text.recentJournals)
                                .font(.headline)
                                .foregroundStyle(QuietNativeTheme.primaryText)

                            ForEach(journals.prefix(3)) { entry in
                                NavigationLink(destination: JournalDetailView(entry: entry)) {
                                    JournalPreviewCard(
                                        entry: entry,
                                        isUnread: JournalUnreadStore.isUnread(entry.id)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 32)
            }
            .quietNativeTabBarClearance()
            .scrollIndicators(.hidden)
            .background(QuietNativeTheme.pageGradient.ignoresSafeArea())
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Image("MyBuddyLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 132, height: 32)
                        .accessibilityLabel("MyBuddy")
                        .accessibilityIdentifier("home.logo")
                }
            }
            .fullScreenCover(isPresented: $showChat, onDismiss: refreshHomeStatus) {
                if let buddy = buddy {
                    ChatView(buddy: buddy)
                        .environmentObject(appState)
                } else {
                    // バディが見つからない場合のフォールバック
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle)
                            .foregroundStyle(.orange)
                        Text(text.missingBuddyTitle)
                            .font(.headline)
                        Text(text.missingBuddyMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button(text.close) { showChat = false }
                            .buttonStyle(.borderedProminent)
                            .tint(.orange)
                    }
                }
            }
            .onAppear {
                refreshHomeStatus()
                #if DEBUG
                print("[Home] buddies: \(buddies.count), states: \(buddyStates.count), journals: \(journals.count)")
                #endif
                #if DEBUG
                print("[Home] buddy: \(buddy?.displayName ?? "nil"), LLM: \(appState.llmStatus)")
                #endif
            }
            .onChange(of: showChat) {
                if !showChat {
                    refreshHomeStatus()
                }
            }
            .onChange(of: journals.count) {
                refreshHomeJournalStatus()
            }
            .onReceive(NotificationCenter.default.publisher(for: .journalUnreadStateDidChange)) { _ in
                refreshHomeJournalStatus()
            }
        }
    }

    private var heroSubtitle: String {
        HomeHeroTextProvider.subtitle(for: buddy, hasTodaySession: hasTodaySession, language: text.resolvedLanguage)
    }

    private var statusMessage: (text: String, tint: Color, icon: String)? {
        switch appState.llmStatus {
        case .loading:
            return (text.aiLoadingMessage, QuietNativeTheme.secondaryText, "sparkles")
        case .error(let msg):
            return (msg, .red, "exclamationmark.triangle.fill")
        default:
            return nil
        }
    }

    @ViewBuilder
    private func statusCard(message: String, tint: Color, icon: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(tint)
            Text(message)
                .font(.footnote)
                .foregroundStyle(QuietNativeTheme.secondaryText)
                .multilineTextAlignment(.leading)
        }
        .padding(16)
        .quietNativeCard(cornerRadius: 22, fill: QuietNativeTheme.surface)
    }

    private func refreshHomeStatus() {
        refreshHomeSessionStatus()
        refreshHomeJournalStatus()
    }

    private func refreshHomeSessionStatus() {
        let today = DayBoundary.appToday()
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today) ?? today
        let descriptor = FetchDescriptor<ConversationSession>(
            predicate: #Predicate<ConversationSession> {
                $0.date >= today && $0.date < tomorrow
            },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        let todaySessions = (try? modelContext.fetch(descriptor)) ?? []
        let dailySessions = todaySessions.filter { $0.type == .daily }
        hasTodaySession = dailySessions.contains { session in
            session.messageCount > 0 || !session.messages.isEmpty
        }
        #if DEBUG
        print("[Home] refreshed sessions: \(todaySessions.count), daily=\(dailySessions.count), hasTodaySession=\(hasTodaySession)")
        #endif
    }

    private func refreshHomeJournalStatus() {
        let today = DayBoundary.appToday()
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today) ?? today
        let appDayStart = DayBoundary.startOfAppDay()
        let appDayEnd = DayBoundary.endOfAppDay()
        var descriptor = FetchDescriptor<JournalEntry>(
            predicate: #Predicate<JournalEntry> {
                ($0.date >= today && $0.date < tomorrow)
                    || ($0.createdAt >= appDayStart && $0.createdAt < appDayEnd)
            }
        )
        descriptor.fetchLimit = 1
        let hasPersistedJournal = ((try? modelContext.fetch(descriptor)) ?? []).isEmpty == false
        let fallbackFlagKey = "home.todayJournalCreated.\(Int(DayBoundary.startOfAppDay().timeIntervalSince1970))"
        let hasFallbackFlag = UserDefaults.standard.bool(forKey: fallbackFlagKey)
        hasTodayJournalBadge = hasPersistedJournal || hasFallbackFlag
        #if DEBUG
        print("[Home] refreshed journals: persisted=\(hasPersistedJournal), fallback=\(hasFallbackFlag), todayBadge=\(hasTodayJournalBadge)")
        #endif
    }
}

enum HomeHeroTextProvider {
    private static let genericFreshSubtitle = "短くても大丈夫。今日の気分や出来事を少しだけ話してみましょう。"
    private static let genericResumeSubtitle = "途中からでも大丈夫。今日の会話の続きを始められます。"
    private static let genericFreshSubtitleEnglish = "Short is enough. Share a small moment from today."
    private static let genericResumeSubtitleEnglish = "You can pick up where today's chat left off."

    static func subtitle(
        for buddy: BuddyProfile?,
        hasTodaySession: Bool,
        language: ResolvedAppLanguage = .japanese
    ) -> String {
        if language == .english {
            return hasTodaySession ? genericResumeSubtitleEnglish : genericFreshSubtitleEnglish
        }

        guard let buddy else {
            return hasTodaySession ? genericResumeSubtitle : genericFreshSubtitle
        }

        let savedSubtitle = savedSubtitle(for: buddy, hasTodaySession: hasTodaySession)
        if !savedSubtitle.isEmpty {
            return savedSubtitle
        }

        let composer = PersonaLineComposer(displayName: buddy.displayName, seed: buddy.seed)
        return hasTodaySession ? composer.heroSubtitleResume() : composer.heroSubtitleFresh()
    }

    private static func savedSubtitle(for buddy: BuddyProfile, hasTodaySession: Bool) -> String {
        let rawSubtitle = hasTodaySession ? buddy.heroSubtitleResume : buddy.heroSubtitleFresh
        return rawSubtitle.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct JournalPreviewCard: View {
    let entry: JournalEntry
    var isUnread = false
    @AppStorage(JournalTypographyStyle.storageKey)
    private var journalTypographyRawValue = JournalTypographyStyle.defaultStyle.rawValue

    private var journalTypography: JournalTypographyStyle {
        JournalTypographyStyle.from(rawValue: journalTypographyRawValue)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let images = entry.imageDataList, !images.isEmpty {
                JournalImageGallery(images: images, layout: .row)
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    HStack(spacing: 6) {
                        Text(entry.formattedDate)
                            .font(.caption)
                            .foregroundStyle(QuietNativeTheme.secondaryText)
                        if isUnread {
                            UnreadDotView(size: 7)
                        }
                    }
                    Spacer()
                    HStack(spacing: 6) {
                        ForEach(entry.normalizedEmotionTags.prefix(2), id: \.self) { tag in
                            Text("#\(tag)")
                                .font(.caption2)
                                .foregroundStyle(QuietNativeTheme.accent)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(QuietNativeTheme.accentSoft)
                                .clipShape(Capsule())
                        }
                    }
                }

                Text(entry.title)
                    .font(.title3.weight(.semibold))
                    .journalTypography(journalTypography)
                    .foregroundStyle(QuietNativeTheme.primaryText)

                Text(entry.summaryText)
                    .font(.subheadline)
                    .journalTypography(journalTypography)
                    .foregroundStyle(QuietNativeTheme.secondaryText)
                    .lineLimit(2)
                    .lineSpacing(journalTypography.summaryLineSpacing)
            }
        }
        .padding(18)
        .quietNativeCard(cornerRadius: 24)
    }
}

private struct CompanionHeroCard: View {
    let buddy: BuddyProfile?
    let seed: BuddySeed
    let state: BuddyState?
    let buttonLabel: String
    let subtitle: String
    let isReady: Bool
    let hasTodayJournalBadge: Bool
    let onStartChat: () -> Void
    @AppStorage(AppLanguageMode.storageKey)
    private var appLanguageRawValue = AppLanguageMode.system.rawValue

    private var text: AppText {
        AppText(language: (AppLanguageMode(rawValue: appLanguageRawValue) ?? .system).resolvedLanguage)
    }

    private var canStartChat: Bool {
        isReady && buddy != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(text.todaysBuddy)
                        .font(.caption)
                        .foregroundStyle(QuietNativeTheme.secondaryText)

                    if let buddy {
                        NavigationLink(destination: BuddyProfileView(buddy: buddy)) {
                            HStack(spacing: 6) {
                                Text(buddy.displayName)
                                    .font(.system(size: 28, weight: .bold))
                                    .foregroundStyle(QuietNativeTheme.primaryText)
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(QuietNativeTheme.secondaryText)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("home.buddyProfileButton")
                    } else {
                        Text("MyBuddy")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(QuietNativeTheme.primaryText)
                    }

                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(QuietNativeTheme.secondaryText)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 12)

                BuddyAvatarView(seed: seed, size: 108)
            }

            HStack(spacing: 8) {
                if let state {
                    Label(text.streakLabel(days: state.streakDays), systemImage: "flame.fill")
                        .foregroundStyle(QuietNativeTheme.accent)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(QuietNativeTheme.accentSoft)
                        .clipShape(Capsule())
                }

                if hasTodayJournalBadge {
                    Label(text.todayDiaryBadge, systemImage: "checkmark.circle.fill")
                        .foregroundStyle(QuietNativeTheme.secondaryText)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(QuietNativeTheme.surface)
                        .clipShape(Capsule())
                        .accessibilityIdentifier("home.todayJournalCreatedBadge")
                }
            }
            .font(.caption.weight(.semibold))

            Button(action: onStartChat) {
                HStack(spacing: 10) {
                    if isReady {
                        Image(systemName: "bubble.left.and.bubble.right.fill")
                    } else {
                        ProgressView()
                            .tint(.white)
                    }
                    Text(buttonLabel)
                        .fontWeight(.semibold)
                }
                .font(.body)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 58)
                .background(canStartChat ? QuietNativeTheme.accent : QuietNativeTheme.secondaryText.opacity(0.55))
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .contentShape(Rectangle())
            }
            .accessibilityIdentifier("home.startChatButton")
            .disabled(!canStartChat)
        }
        .padding(22)
        .background(QuietNativeTheme.heroGradient)
        .overlay(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .stroke(Color.white.opacity(0.6), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .shadow(color: Color.black.opacity(0.08), radius: 22, y: 10)
    }
}
