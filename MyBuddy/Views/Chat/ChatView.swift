import SwiftUI
import SwiftData
import PhotosUI

struct ChatView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(AppLanguageMode.storageKey)
    private var appLanguageRawValue = AppLanguageMode.system.rawValue
    @StateObject private var viewModel = ChatViewModel()

    let buddy: BuddyProfile

    @FocusState private var isInputFocused: Bool
    @State private var showJournalPreview = false
    @State private var photosPickerItem: PhotosPickerItem?
    @State private var diaryButtonFlash = false
    @State private var flashTask: Task<Void, Never>?

    private let visionUIEnabled = true
    private var text: AppText {
        let mode = AppLanguageMode(rawValue: appLanguageRawValue) ?? .system
        return AppText(language: mode.resolvedLanguage)
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 16) {
                        diaryStatusCard

                        ForEach(viewModel.messages) { message in
                            if !message.text.isEmpty || message.image != nil {
                                MessageBubbleView(
                                    text: message.text,
                                    isFromBuddy: message.isFromBuddy,
                                    buddyName: buddy.displayName,
                                    buddySeed: buddy.seed,
                                    image: message.image
                                )
                                .id(message.id)
                            }
                        }

                        // タイピングインジケーター（ストリーミング開始でテキストが入ったら非表示に切り替え）
                        if viewModel.isTyping && !(viewModel.messages.last.map { $0.isFromBuddy && !$0.text.isEmpty } ?? false) {
                            TypingIndicator()
                                .id("typing")
                        }

                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 16)
                }
                .scrollIndicators(.hidden)
                .contentMargins(.top, 20, for: .scrollContent)
                .background(QuietNativeTheme.pageGradient.ignoresSafeArea())
                .safeAreaInset(edge: .bottom) {
                    VStack(spacing: 8) {
                        if viewModel.shouldSuggestDiary {
                            diarySuggestToast
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                        inputBar
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
                    .animation(.easeInOut(duration: 0.25), value: viewModel.shouldSuggestDiary)
                }
                .onAppear {
                    // セッション再開時: メッセージが既にある場合、レイアウト完了後に最下部へスクロール
                    if !viewModel.messages.isEmpty {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            proxy.scrollTo("bottom", anchor: .bottom)
                        }
                    }
                }
                .onChange(of: viewModel.messages.count) { oldCount, newCount in
                    if oldCount == 0 {
                        // 初回ロード時はレイアウト完了を待ってから最下部へ
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            proxy.scrollTo("bottom", anchor: .bottom)
                        }
                    } else {
                        withAnimation {
                            proxy.scrollTo("bottom", anchor: .bottom)
                        }
                    }
                }
                .onChange(of: viewModel.isTyping) {
                    withAnimation {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                }
                .onChange(of: viewModel.streamingUpdateCount) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .top, spacing: 0) {
                chatNavigationBar
            }
            .sheet(isPresented: $showJournalPreview) {
                if let result = viewModel.journalResult {
                    JournalPreviewSheet(result: result, buddyName: buddy.displayName) {
                        showJournalPreview = false
                    }
                } else if let entry = viewModel.existingJournalEntry {
                    JournalPreviewSheet(
                        result: JournalGenerationResult(
                            title: entry.title,
                            body: entry.fullDiaryText,
                            summary: entry.summaryText,
                            emotionTags: entry.normalizedEmotionTags,
                            tomorrowNote: entry.tomorrowNote,
                            imageDataList: entry.imageDataList
                        ),
                        buddyName: buddy.displayName
                    ) {
                        showJournalPreview = false
                    }
                }
            }
            .onChange(of: viewModel.diaryUpdatedToastTick) { _, _ in
                // 日記が更新された瞬間にツールバーアイコンをフラッシュさせる
                flashTask?.cancel()
                withAnimation(.easeOut(duration: 0.25)) {
                    diaryButtonFlash = true
                }
                flashTask = Task {
                    try? await Task.sleep(for: .seconds(1.2))
                    guard !Task.isCancelled else { return }
                    withAnimation(.easeIn(duration: 0.5)) {
                        diaryButtonFlash = false
                    }
                }
            }
            .onChange(of: viewModel.diaryPresentationTick) { _, _ in
                showJournalPreview = true
            }
        }
        .overlay {
            if viewModel.isShowingDiaryLoadingModal {
                DiaryLoadingOverlay(
                    buddyName: buddy.displayName,
                    buddySeed: buddy.seed,
                    message: viewModel.diaryLoadingMessage,
                    onClose: { viewModel.cancelDiaryCompilationFromModal() }
                )
            }
        }
        .onAppear {
            viewModel.setup(
                buddy: buddy,
                llmService: appState.llmService,
                modelContext: modelContext
            )
            viewModel.presentDiaryLoadingIfNeeded()
        }
        .onDisappear {
            // 日記画面への遷移時は日記アイコンタップで既にトリガー済みなので二重発火を抑制
            if !showJournalPreview {
                viewModel.scheduleDiaryUpdateOnExit()
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background {
                viewModel.triggerDiaryFromBackground()
            } else if newPhase == .active {
                viewModel.presentDiaryLoadingIfNeeded()
            }
        }
    }

    private var chatNavigationBar: some View {
        ZStack {
            Text(buddy.displayName)
                .font(.headline.weight(.semibold))
                .foregroundStyle(QuietNativeTheme.primaryText)
                .lineLimit(1)

            HStack {
                Button(text.close) { dismiss() }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(QuietNativeTheme.accent)
                    .frame(minWidth: 56, minHeight: 44, alignment: .leading)
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("chat.closeButton")

                Spacer()

                diaryToolbarButton
                    .frame(minWidth: 92, minHeight: 44, alignment: .trailing)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 58)
        .background(.ultraThinMaterial)
    }

    @ViewBuilder
    private var diaryToolbarButton: some View {
        if viewModel.shouldShowDiaryToolbarButton {
            HStack(spacing: 6) {
                Image(systemName: "book.fill")
                Text(viewModel.diaryToolbarTitle)
                    .font(.caption2.weight(.semibold))
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(diaryButtonFlash ? Color.pink : (viewModel.canTriggerDiaryCompilation ? QuietNativeTheme.accent : QuietNativeTheme.secondaryText))
            .scaleEffect(diaryButtonFlash ? 1.04 : 1.0)
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
            .onTapGesture {
                guard viewModel.canTriggerDiaryCompilation else { return }
                viewModel.triggerDiaryFromIconTap()
            }
            .accessibilityAddTraits(.isButton)
            .accessibilityRespondsToUserInteraction(viewModel.canTriggerDiaryCompilation)
            .accessibilityLabel(viewModel.diaryToolbarTitle)
            .accessibilityIdentifier("chat.viewJournalButton")
        } else if viewModel.shouldShowDiaryPreparingIndicator {
            HStack(spacing: 4) {
                ProgressView()
                    .controlSize(.small)
                Text(viewModel.shouldShowDiaryUpdatingIndicator ? text.diaryUpdating : text.diaryPreparing)
                    .font(.caption2)
                    .foregroundStyle(QuietNativeTheme.secondaryText)
            }
        }
    }

    private var diarySuggestToast: some View {
        HStack(spacing: 10) {
            Image(systemName: "book.closed.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(QuietNativeTheme.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(text.diarySuggestTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(QuietNativeTheme.primaryText)
                Text(text.diarySuggestSubtitle)
                    .font(.caption2)
                    .foregroundStyle(QuietNativeTheme.secondaryText)
            }
            Spacer(minLength: 8)
            Button {
                viewModel.acceptDiarySuggestion()
            } label: {
                Text(text.create)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(QuietNativeTheme.accent))
            }
            .accessibilityIdentifier("chat.diarySuggest.accept")
            Button {
                viewModel.dismissDiarySuggestion()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(QuietNativeTheme.secondaryText)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(QuietNativeTheme.surface))
            }
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
            .accessibilityIdentifier("chat.diarySuggest.dismiss")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .quietNativeCard(cornerRadius: 18, fill: QuietNativeTheme.accentSoft)
        .accessibilityIdentifier("chat.diarySuggestToast")
    }

    private var inputBar: some View {
        VStack(spacing: 0) {
            if let image = viewModel.selectedImage {
                HStack {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 80, height: 80)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(alignment: .topTrailing) {
                            Button(action: { viewModel.clearAttachedImage() }) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 20))
                                    .foregroundStyle(.white, .black.opacity(0.6))
                                    .frame(minWidth: 44, minHeight: 44)
                                    .contentShape(Rectangle())
                            }
                            .offset(x: 6, y: -6)
                        }
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.top, 14)
            }

            if visionUIEnabled && viewModel.isLoadingVision {
                HStack(spacing: 8) {
                    ProgressView()
                    Text(text.visionLoading)
                        .font(.caption)
                        .foregroundStyle(QuietNativeTheme.secondaryText)
                }
                .padding(.top, 10)
            }

            HStack(spacing: 8) {
                if visionUIEnabled {
                    PhotosPicker(selection: $photosPickerItem, matching: .images) {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(canAttachImage ? QuietNativeTheme.accent : QuietNativeTheme.secondaryText.opacity(0.5))
                            .frame(width: 40, height: 40)
                            .background(QuietNativeTheme.surface)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
                    .disabled(!canAttachImage)
                    .onChange(of: photosPickerItem) {
                        guard let item = photosPickerItem else { return }
                        photosPickerItem = nil
                        Task {
                            await viewModel.attachImage(from: item)
                        }
                    }
                }

                TextField(text.chatPlaceholder, text: $viewModel.inputText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...4)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(QuietNativeTheme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .focused($isInputFocused)
                    .accessibilityIdentifier("chat.inputField")

                Button(action: { viewModel.sendMessage() }) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 42, height: 42)
                        .background(canSend ? QuietNativeTheme.accent : QuietNativeTheme.secondaryText.opacity(0.4))
                        .clipShape(Circle())
                }
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Circle())
                .accessibilityIdentifier("chat.sendButton")
                .disabled(!canSend)
            }
            .padding(14)
        }
        .quietNativeGlass()
    }

    @ViewBuilder
    private var diaryStatusCard: some View {
        if viewModel.canOpenExistingJournal {
            Button {
                showJournalPreview = true
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "book.closed.fill")
                        .foregroundStyle(QuietNativeTheme.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(text.todayDiaryAvailable)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(QuietNativeTheme.primaryText)
                        Text(text.diaryUpdatesWhileChatting)
                            .font(.caption)
                            .foregroundStyle(QuietNativeTheme.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(QuietNativeTheme.secondaryText)
                }
                .padding(16)
                .quietNativeCard(cornerRadius: 22)
            }
            .buttonStyle(.plain)
        } else if viewModel.shouldShowDiaryPreparingIndicator {
            HStack(spacing: 10) {
                ProgressView()
                    .tint(QuietNativeTheme.accent)
                Text(viewModel.shouldShowDiaryUpdatingIndicator
                     ? text.diaryUpdatingLong
                     : text.diaryPreparingLong)
                    .font(.footnote)
                    .foregroundStyle(QuietNativeTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
            }
            .padding(14)
            .quietNativeCard(cornerRadius: 20, fill: QuietNativeTheme.accentSoft)
        } else if viewModel.shouldShowDiaryToolbarButton {
            HStack(spacing: 10) {
                Image(systemName: "book.closed")
                    .foregroundStyle(QuietNativeTheme.accent)
                Text(viewModel.hasJournal
                     ? text.diaryStatusUpdateHint
                     : text.diaryStatusCreateHint)
                    .font(.footnote)
                    .foregroundStyle(QuietNativeTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
            }
            .padding(14)
            .quietNativeCard(cornerRadius: 20, fill: QuietNativeTheme.accentSoft)
        }
    }

    private var canSend: Bool {
        let hasText = !viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasImage = viewModel.selectedImage != nil
        return (hasText || hasImage) && !viewModel.isTyping
    }

    private var canAttachImage: Bool {
        viewModel.imageAttachCount < ChatViewModel.maxImageAttachments
    }
}

struct DiaryLoadingOverlay: View {
    let buddyName: String
    var buddySeed: BuddySeed? = nil
    let message: String
    let onClose: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.22)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                HStack {
                    Spacer()
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(QuietNativeTheme.secondaryText)
                            .frame(width: 28, height: 28)
                            .background(QuietNativeTheme.surface)
                            .clipShape(Circle())
                    }
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
                    .accessibilityIdentifier("chat.diaryLoadingCloseButton")
                }

                BuddyAvatarView(seed: buddySeed, size: 72, showAnimation: true)

                VStack(spacing: 6) {
                    Text(buddyName)
                        .font(.headline)
                        .foregroundStyle(QuietNativeTheme.primaryText)
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(QuietNativeTheme.secondaryText)
                }

                ProgressView()
                    .tint(QuietNativeTheme.accent)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
            .frame(maxWidth: 280)
            .quietNativeCard(cornerRadius: 28)
        }
        .transition(.opacity)
        .allowsHitTesting(true)
        .accessibilityIdentifier("chat.diaryLoadingModal")
    }
}

// MARK: - Message Bubble

struct MessageBubbleView: View {
    let text: String
    let isFromBuddy: Bool
    let buddyName: String
    var buddySeed: BuddySeed? = nil
    var image: UIImage? = nil

    var body: some View {
        if isFromBuddy {
            HStack(alignment: .top, spacing: 8) {
                BuddyAvatarView(seed: buddySeed, size: 32, showAnimation: false)

                VStack(alignment: .leading, spacing: 6) {
                    Text(buddyName)
                        .font(.caption2)
                        .foregroundStyle(QuietNativeTheme.secondaryText)
                    Text(text)
                        .font(.body)
                        .foregroundStyle(QuietNativeTheme.primaryText)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(QuietNativeTheme.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(QuietNativeTheme.line, lineWidth: 1)
                        )
                        .accessibilityIdentifier("chat.buddyMessageText")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            HStack {
                Spacer(minLength: 40)
                VStack(alignment: .trailing, spacing: 6) {
                    if let image {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(maxWidth: 200, maxHeight: 200)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(Color.white.opacity(0.7), lineWidth: 1)
                            )
                    }
                    if !text.isEmpty {
                        Text(text)
                            .font(.body)
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .background(QuietNativeTheme.accent)
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .accessibilityIdentifier("chat.userMessageText")
                    }
                }
            }
        }
    }
}

// MARK: - Typing Indicator

struct TypingIndicator: View {
    @State private var dotCount = 0

    var body: some View {
        HStack {
            HStack(spacing: 4) {
                ForEach(0..<3) { index in
                    Circle()
                        .fill(QuietNativeTheme.secondaryText)
                        .frame(width: 6, height: 6)
                        .opacity(dotCount == index ? 1 : 0.3)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(QuietNativeTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(QuietNativeTheme.line, lineWidth: 1)
            )
            .padding(.leading, 56)

            Spacer()
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(400))
                dotCount = (dotCount + 1) % 3
            }
        }
    }
}

// MARK: - Journal Generating Indicator

struct JournalGeneratingIndicator: View {
    let isUpdate: Bool
    let buddyName: String
    var buddySeed: BuddySeed? = nil
    let comment: String
    @AppStorage(AppLanguageMode.storageKey)
    private var appLanguageRawValue = AppLanguageMode.system.rawValue

    private var text: AppText {
        let mode = AppLanguageMode(rawValue: appLanguageRawValue) ?? .system
        return AppText(language: mode.resolvedLanguage)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            // バディアバター
            BuddyAvatarView(seed: buddySeed, size: 32, showAnimation: false)

            VStack(alignment: .leading, spacing: 6) {
                Text(buddyName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                // バディのコメント
                if !comment.isEmpty {
                    Text(comment)
                        .font(.body)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(QuietNativeTheme.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }

                HStack(spacing: 6) {
                    ProgressView()
                        .tint(QuietNativeTheme.accent)
                    Text(isUpdate ? text.diaryGeneratingUpdate : text.diaryGeneratingNew)
                        .font(.caption)
                        .foregroundStyle(QuietNativeTheme.secondaryText)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(QuietNativeTheme.accentSoft)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }

            Spacer(minLength: 24)
        }
    }
}

// MARK: - Journal Notification Banner

struct JournalNotificationBanner: View {
    let isNew: Bool
    let onTap: () -> Void
    @AppStorage(AppLanguageMode.storageKey)
    private var appLanguageRawValue = AppLanguageMode.system.rawValue

    private var text: AppText {
        let mode = AppLanguageMode(rawValue: appLanguageRawValue) ?? .system
        return AppText(language: mode.resolvedLanguage)
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                Image(systemName: isNew ? "book.fill" : "book.and.wrench.fill")
                    .font(.title3)
                    .foregroundStyle(isNew ? QuietNativeTheme.accent : .blue)

                VStack(alignment: .leading, spacing: 2) {
                    Text(isNew ? text.diaryCreated : text.diaryUpdated)
                        .font(isNew ? .subheadline.bold() : .caption)
                        .foregroundStyle(QuietNativeTheme.primaryText)
                    if isNew {
                        Text(text.tapToRead)
                            .font(.caption)
                            .foregroundStyle(QuietNativeTheme.secondaryText)
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, isNew ? 14 : 10)
            .quietNativeGlass(cornerRadius: 18)
        }
    }
}

// MARK: - Journal Preview Sheet

struct JournalPreviewSheet: View {
    let result: JournalGenerationResult
    var buddyName: String = ""
    let onDone: () -> Void
    @AppStorage(JournalTypographyStyle.storageKey)
    private var journalTypographyRawValue = JournalTypographyStyle.defaultStyle.rawValue
    @AppStorage(AppLanguageMode.storageKey)
    private var appLanguageRawValue = AppLanguageMode.system.rawValue

    private var journalTypography: JournalTypographyStyle {
        JournalTypographyStyle.from(rawValue: journalTypographyRawValue)
    }

    private var text: AppText {
        let mode = AppLanguageMode(rawValue: appLanguageRawValue) ?? .system
        return AppText(language: mode.resolvedLanguage)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let images = result.imageDataList, !images.isEmpty {
                        JournalImageGallery(images: images, layout: .preview)
                    }

                    // 感情タグ
                    FlowLayout(spacing: 6) {
                        ForEach(JournalEntry.normalizeEmotionTags(result.emotionTags), id: \.self) { tag in
                            Text("#\(tag)")
                                .font(.caption)
                                .foregroundStyle(QuietNativeTheme.accent)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(QuietNativeTheme.accentSoft)
                                .clipShape(Capsule())
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("chat.journalPreviewEmotionTags")

                    // 本文
                    Text(result.body)
                        .font(journalTypography.bodyFont)
                        .journalTypography(journalTypography)
                        .lineSpacing(journalTypography.bodyLineSpacing)
                        .accessibilityIdentifier("chat.journalPreviewBody")

                    // バディからの一言
                    if !result.tomorrowNote.isEmpty {
                        Divider()
                        VStack(alignment: .leading, spacing: 6) {
                            Text(text.isEnglish
                                 ? "\(text.buddyNoteTitle) \(buddyName.isEmpty ? text.buddyDefaultName : buddyName)"
                                 : "\(buddyName.isEmpty ? text.buddyDefaultName : buddyName)からの一言")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(QuietNativeTheme.accent)
                            Text(result.tomorrowNote)
                                .font(journalTypography.noteFont)
                                .journalTypography(journalTypography)
                                .foregroundStyle(QuietNativeTheme.secondaryText)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("chat.journalPreviewTomorrowNote")
                    }
                }
                .padding(20)
            }
            .background(QuietNativeTheme.pageGradient.ignoresSafeArea())
            .navigationTitle(result.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(text.done, action: onDone)
                        .fontWeight(.semibold)
                        .accessibilityIdentifier("chat.journalPreviewDoneButton")
                }
            }
        }
    }
}
