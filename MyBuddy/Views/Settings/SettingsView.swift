import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appState: AppState
    @Query private var buddies: [BuddyProfile]
    @AppStorage(AppLanguageMode.storageKey)
    private var appLanguageRawValue = AppLanguageMode.system.rawValue

    @State private var showResetConfirm = false
    @State private var appearancePickerState: AppearancePickerState?

    private var text: AppText {
        AppText(language: selectedLanguageMode.resolvedLanguage)
    }

    private var selectedLanguageMode: AppLanguageMode {
        AppLanguageMode(rawValue: appLanguageRawValue) ?? .system
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    appInfoSection
                    languageSection
                    buddyManagementSection
                    legalSection
                    resetSection
                }
                .padding(.horizontal)
                .padding(.top, 16)
                .quietNativeTabBarClearance()
            }
            .background(QuietNativeTheme.pageGradient)
            .navigationTitle(text.settingsTitle)
            .sheet(item: $appearancePickerState) { pickerState in
                if let buddy = buddies.first {
                    AppearanceCandidateSheet(
                        buddyName: pickerState.buddyName,
                        initialKind: pickerState.selectedKind,
                        candidateGroups: pickerState.candidateGroups,
                        onSelect: { seed in
                            applyAppearance(seed, to: buddy)
                            appearancePickerState = nil
                        },
                        onClose: {
                            appearancePickerState = nil
                        }
                    )
                }
            }
        }
    }

    private var appInfoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(text.appInfo)
                .font(.headline)
                .foregroundStyle(QuietNativeTheme.primaryText)

            VStack(spacing: 8) {
                HStack {
                    Text(text.version)
                        .foregroundStyle(QuietNativeTheme.secondaryText)
                    Spacer()
                    Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "-")
                        .foregroundStyle(QuietNativeTheme.primaryText)
                }
            }
            .font(.subheadline)
            .padding(16)
            .quietNativeCard(cornerRadius: 22)
        }
    }

    private var languageSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(text.languageTitle)
                .font(.headline)
                .foregroundStyle(QuietNativeTheme.primaryText)

            VStack(alignment: .leading, spacing: 10) {
                Text(text.appLanguageDescription)
                    .font(.caption)
                    .foregroundStyle(QuietNativeTheme.secondaryText)

                Picker(text.appLanguage, selection: $appLanguageRawValue) {
                    ForEach(AppLanguageMode.allCases) { mode in
                        Text(text.isEnglish ? mode.displayName : mode.localizedDisplayName)
                            .tag(mode.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("settings.languagePicker")
            }
            .padding(16)
            .quietNativeCard(cornerRadius: 22)
        }
    }

    private var buddyManagementSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(text.buddySettings)
                .font(.headline)
                .foregroundStyle(QuietNativeTheme.primaryText)

            VStack(alignment: .leading, spacing: 12) {
                if let buddy = buddies.first {
                    HStack(spacing: 14) {
                        BuddyAvatarView(seed: buddy.seed, size: 56, showAnimation: false)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(buddy.displayName)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(QuietNativeTheme.primaryText)
                            Text(text.appearanceDescription)
                                .font(.caption)
                                .foregroundStyle(QuietNativeTheme.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                            Text("\(text.currentAppearance): \(text.appearanceKindName(for: BuddyAppearanceKind(characterType: buddy.characterType)))")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(QuietNativeTheme.accent)
                                .accessibilityIdentifier("settings.currentAppearanceKind")
                        }
                    }

                    Button {
                        let selectedKind = BuddyAppearanceKind(characterType: buddy.characterType)
                        let groups = BuddyAppearanceKind.allCases.map { kind in
                            AppearanceCandidateGroup(
                                kind: kind,
                                candidates: BuddyAppearanceCandidateFactory.makeCandidates(from: buddy, kind: kind)
                            )
                        }
                        appearancePickerState = AppearancePickerState(
                            buddyName: buddy.displayName,
                            selectedKind: selectedKind,
                            candidateGroups: groups
                        )
                    } label: {
                        HStack {
                            Image(systemName: "sparkles")
                            Text(hasChangedAppearanceToday ? text.changedToday : text.changeAppearance)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(hasChangedAppearanceToday ? QuietNativeTheme.secondaryText : QuietNativeTheme.accent)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(hasChangedAppearanceToday)
                    .accessibilityIdentifier("settings.changeAppearanceButton")

                    Text(hasChangedAppearanceToday ? text.appearanceLimitChanged : text.appearanceLimitAvailable)
                        .font(.caption)
                        .foregroundStyle(QuietNativeTheme.secondaryText)
                } else {
                    Text(text.buddySettingsUnavailable)
                        .font(.subheadline)
                        .foregroundStyle(QuietNativeTheme.secondaryText)
                }
            }
            .padding(16)
            .quietNativeCard(cornerRadius: 22)
        }
    }

    private var hasChangedAppearanceToday: Bool {
        UserDefaults.standard.bool(forKey: BuddyAppearanceCandidateFactory.dailyChangeKey())
    }

    private func applyAppearance(_ seed: BuddySeed, to buddy: BuddyProfile) {
        BuddyAppearanceCandidateFactory.applyVisual(from: seed, to: buddy)
        UserDefaults.standard.set(true, forKey: BuddyAppearanceCandidateFactory.dailyChangeKey())
        try? modelContext.save()
    }

    private var legalSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(text.policies)
                .font(.headline)
                .foregroundStyle(QuietNativeTheme.primaryText)

            VStack(spacing: 0) {
                legalRow(
                    icon: "lock.shield",
                    title: text.privacyPolicy,
                    destination: LegalDocumentView(
                        title: text.privacyPolicy,
                        content: AppLegalContent.privacyPolicy(language: text.resolvedLanguage)
                    )
                )
                Divider().padding(.leading, 48)
                legalRow(
                    icon: "doc.text",
                    title: text.termsOfService,
                    destination: LegalDocumentView(
                        title: text.termsOfService,
                        content: AppLegalContent.termsOfService(language: text.resolvedLanguage)
                    )
                )
                Divider().padding(.leading, 48)
                legalRow(
                    icon: "text.book.closed",
                    title: text.ossLicenses,
                    destination: LegalDocumentView(
                        title: text.ossLicenses,
                        content: AppLegalContent.openSourceLicenses(language: text.resolvedLanguage)
                    )
                )
            }
            .quietNativeCard(cornerRadius: 22)
        }
    }

    private func legalRow<Destination: View>(
        icon: String,
        title: String,
        destination: Destination
    ) -> some View {
        NavigationLink {
            destination
        } label: {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(QuietNativeTheme.accent)
                    .frame(width: 24)
                Text(title)
                    .font(.body)
                    .foregroundStyle(QuietNativeTheme.primaryText)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(QuietNativeTheme.secondaryText)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var resetSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(text.dataManagement)
                .font(.headline)
                .foregroundStyle(QuietNativeTheme.primaryText)

            Button(role: .destructive) {
                showResetConfirm = true
            } label: {
                HStack {
                    Image(systemName: "arrow.counterclockwise")
                    Text(text.resetBuddyAndDiary)
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
        }
    }

    private func resetAllData() {
        deleteAll(ChatMessage.self)
        deleteAll(DiaryNote.self)
        deleteAll(BuddyProfile.self)
        deleteAll(BuddyState.self)
        deleteAll(ConversationSession.self)
        deleteAll(JournalEntry.self)
        deleteAll(UserProfile.self)

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

    private func deleteAll<T: PersistentModel>(_ type: T.Type) {
        let descriptor = FetchDescriptor<T>()
        let items = (try? modelContext.fetch(descriptor)) ?? []
        for item in items {
            modelContext.delete(item)
        }
    }
}

private struct AppearancePickerState: Identifiable {
    let id = UUID()
    let buddyName: String
    let selectedKind: BuddyAppearanceKind
    let candidateGroups: [AppearanceCandidateGroup]
}

private struct AppearanceCandidateGroup: Identifiable {
    let kind: BuddyAppearanceKind
    let candidates: [BuddySeed]

    var id: BuddyAppearanceKind { kind }
}

private struct AppearanceCandidateSheet: View {
    let buddyName: String
    @State private var selectedKind: BuddyAppearanceKind
    @State private var previewState: AppearancePreviewState?
    @AppStorage(AppLanguageMode.storageKey)
    private var appLanguageRawValue = AppLanguageMode.system.rawValue
    let candidateGroups: [AppearanceCandidateGroup]
    let onSelect: (BuddySeed) -> Void
    let onClose: () -> Void

    private let columns = Array(repeating: GridItem(.flexible(minimum: 92), spacing: 12), count: 3)
    private var text: AppText {
        AppText(language: (AppLanguageMode(rawValue: appLanguageRawValue) ?? .system).resolvedLanguage)
    }

    init(
        buddyName: String,
        initialKind: BuddyAppearanceKind,
        candidateGroups: [AppearanceCandidateGroup],
        onSelect: @escaping (BuddySeed) -> Void,
        onClose: @escaping () -> Void
    ) {
        self.buddyName = buddyName
        self._selectedKind = State(initialValue: initialKind)
        self.candidateGroups = candidateGroups
        self.onSelect = onSelect
        self.onClose = onClose
    }

    private var selectedCandidates: [BuddySeed] {
        candidateGroups.first(where: { $0.kind == selectedKind })?.candidates ?? []
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                Text(text.appearanceCandidateTitle(for: buddyName))
                    .font(.title3.bold())
                    .foregroundStyle(QuietNativeTheme.primaryText)
                    .padding(.top, 8)

                Text(text.appearanceCandidateDescription)
                    .font(.subheadline)
                    .foregroundStyle(QuietNativeTheme.secondaryText)

                HStack(spacing: 10) {
                    ForEach(BuddyAppearanceKind.allCases) { kind in
                        Button {
                            selectedKind = kind
                        } label: {
                            VStack(spacing: 4) {
                                Text(text.appearanceKindName(for: kind))
                                    .font(.subheadline.weight(.semibold))
                                Text(text.appearanceKindDescription(for: kind))
                                    .font(.caption2)
                            }
                            .foregroundStyle(selectedKind == kind ? .white : QuietNativeTheme.secondaryText)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(selectedKind == kind ? QuietNativeTheme.accent : QuietNativeTheme.surface)
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .stroke(selectedKind == kind ? QuietNativeTheme.accent.opacity(0.45) : QuietNativeTheme.line, lineWidth: 1)
                            )
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("settings.appearanceType.\(kind.rawValue)")
                    }
                }

                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(Array(selectedCandidates.enumerated()), id: \.offset) { index, seed in
                        Button {
                            previewState = AppearancePreviewState(seed: seed)
                        } label: {
                            VStack(spacing: 10) {
                                BuddyAvatarView(seed: seed, size: 78, showAnimation: false)
                                    .frame(width: 78, height: 78)
                                VStack(spacing: 2) {
                                    Text(text.appearanceDisplayName(for: seed))
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(QuietNativeTheme.primaryText)
                                    Text(text.candidateLabel(index: index + 1))
                                        .font(.caption2)
                                        .foregroundStyle(QuietNativeTheme.secondaryText)
                                }
                            }
                            .padding(.vertical, 14)
                            .frame(maxWidth: .infinity)
                            .frame(height: 132)
                            .background(QuietNativeTheme.surface)
                            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 22, style: .continuous)
                                    .stroke(QuietNativeTheme.line, lineWidth: 1)
                            )
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("settings.appearanceCandidate.\(seed.characterType).\(index + 1)")
                    }
                }
                .id(selectedKind)
                .transaction { transaction in
                    transaction.animation = nil
                }

                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
            .background(QuietNativeTheme.pageGradient.ignoresSafeArea())
            .sheet(item: $previewState) { preview in
                AppearancePreviewSheet(
                    buddyName: buddyName,
                    seed: preview.seed,
                    language: text.resolvedLanguage,
                    onConfirm: {
                        onSelect(preview.seed)
                        previewState = nil
                    },
                    onCancel: {
                        previewState = nil
                    }
                )
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(text.close, action: onClose)
                }
            }
        }
    }
}

private struct AppearancePreviewState: Identifiable {
    let id = UUID()
    let seed: BuddySeed
}

private struct AppearancePreviewSheet: View {
    let buddyName: String
    let seed: BuddySeed
    let language: ResolvedAppLanguage
    let onConfirm: () -> Void
    let onCancel: () -> Void

    private var text: AppText {
        AppText(language: language)
    }

    private var kindName: String {
        text.appearanceDisplayName(for: seed)
    }

    var body: some View {
        VStack(spacing: 22) {
            Capsule()
                .fill(QuietNativeTheme.line)
                .frame(width: 44, height: 5)
                .padding(.top, 10)

            VStack(spacing: 8) {
                Text(text.appearancePreviewTitle)
                    .font(.title3.bold())
                    .foregroundStyle(QuietNativeTheme.primaryText)

                Text("\(kindName)\(text.appearancePreviewDescriptionSuffix)")
                    .font(.subheadline)
                    .foregroundStyle(QuietNativeTheme.secondaryText)
                    .multilineTextAlignment(.center)
            }

            ZStack {
                Circle()
                    .fill(QuietNativeTheme.accentSoft)
                    .frame(width: 220, height: 220)

                BuddyAvatarView(seed: seed, size: 190, showAnimation: false)
                    .frame(width: 190, height: 190)
                    .accessibilityIdentifier("settings.appearancePreviewAvatar")
            }
            .padding(.vertical, 8)

            VStack(spacing: 12) {
                Button {
                    onConfirm()
                } label: {
                    Text(text.confirmAppearanceLabel(for: buddyName))
                        .font(.body.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(QuietNativeTheme.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("settings.confirmAppearanceButton")

                Button {
                    onCancel()
                } label: {
                    Text(text.returnToCandidates)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(QuietNativeTheme.secondaryText)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("settings.cancelAppearancePreviewButton")
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
        .background(QuietNativeTheme.pageGradient.ignoresSafeArea())
    }
}
