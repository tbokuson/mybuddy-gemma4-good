import SwiftUI
import SwiftData

struct OnboardingFlowView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.modelContext) private var modelContext
    @StateObject private var viewModel = OnboardingViewModel()
    @AppStorage(AppLanguageMode.storageKey) private var languageModeRawValue = AppLanguageMode.system.rawValue

    private var text: AppText {
        AppText(language: (AppLanguageMode(rawValue: languageModeRawValue) ?? .system).resolvedLanguage)
    }

    var body: some View {
        ZStack {
            QuietNativeTheme.pageGradient
                .ignoresSafeArea()

            VStack(spacing: 0) {
                if viewModel.currentStep == .naming || viewModel.currentStep == .waitingForLLM || viewModel.currentStep == .chat {
                    OnboardingProgressHeader(currentStep: viewModel.currentStep)
                } else {
                    Color.clear
                        .frame(height: 38)
                        .padding(.top, 16)
                        .padding(.bottom, 10)
                }

                if viewModel.currentStep == .chat {
                    OnboardingChatView(viewModel: viewModel)
                } else {
                    GeometryReader { proxy in
                        ScrollView {
                            VStack(spacing: 0) {
                                Spacer(minLength: 24)

                                switch viewModel.currentStep {
                                case .welcome:
                                    WelcomeStepView(onNext: { viewModel.nextStep() })
                                case .privacy:
                                    PrivacyStepView(onNext: { viewModel.nextStep() })
                                case .naming:
                                    NamingStepView(
                                        name: $viewModel.buddyName,
                                        onComplete: { viewModel.proceedAfterNaming() }
                                    )
                                case .waitingForLLM:
                                    LLMWaitingView(buddyName: viewModel.buddyName.isEmpty ? text.buddyDefaultName : viewModel.buddyName)
                                        .onChange(of: appState.isLLMReady) {
                                            if appState.isLLMReady {
                                                viewModel.onLLMReady()
                                            }
                                        }
                                case .choosingAppearance:
                                    ChoosingAppearanceView(viewModel: viewModel)
                                case .extracting:
                                    ExtractingView(buddyName: viewModel.buddyName.isEmpty ? text.buddyDefaultName : viewModel.buddyName)
                                case .reveal:
                                    BuddyRevealView(
                                        seed: viewModel.generatedSeed,
                                        buddyName: viewModel.buddyName.isEmpty ? text.buddyDefaultName : viewModel.buddyName,
                                        greeting: viewModel.revealGreeting,
                                        onComplete: {
                                            viewModel.completeBuddyCreation(modelContext: modelContext)
                                            viewModel.nextStep()
                                        },
                                        onRetry: { viewModel.retryFromReveal() }
                                    )
                                case .complete:
                                    OnboardingCompleteView()
                                case .chat:
                                    EmptyView()
                                }

                                Spacer(minLength: 24)
                            }
                            .frame(maxWidth: .infinity, minHeight: proxy.size.height)
                        }
                        .scrollBounceBehavior(.basedOnSize)
                        .scrollIndicators(.hidden)
                    }
                }
            }
        }
        .animation(.easeInOut(duration: 0.3), value: viewModel.currentStep)
        .onAppear {
            viewModel.configure(llmService: appState.llmService, modelContext: modelContext)
        }
    }
}

private struct OnboardingProgressHeader: View {
    let currentStep: OnboardingViewModel.OnboardingStep
    @AppStorage(AppLanguageMode.storageKey) private var languageModeRawValue = AppLanguageMode.system.rawValue

    private var text: AppText {
        AppText(language: (AppLanguageMode(rawValue: languageModeRawValue) ?? .system).resolvedLanguage)
    }

    private var progress: Double? {
        switch currentStep {
        case .naming:
            1.0 / 3.0
        case .chat, .waitingForLLM:
            2.0 / 3.0
        default:
            nil
        }
    }

    var body: some View {
        VStack(spacing: 10) {
            if let progress {
                ProgressView(value: progress, total: 1)
                    .tint(QuietNativeTheme.accent)
                    .accessibilityIdentifier("onboarding.stepProgressBar")

                Text(progressLabel)
                    .font(.caption)
                    .foregroundStyle(QuietNativeTheme.secondaryText)
            } else {
                Color.clear.frame(height: 12)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 16)
        .padding(.bottom, 10)
    }

    private var progressLabel: String {
        switch currentStep {
        case .naming:
            text.onboardingProgressNaming
        case .chat, .waitingForLLM:
            text.onboardingProgressChat
        default:
            ""
        }
    }
}

// MARK: - Welcome Step

struct WelcomeStepView: View {
    let onNext: () -> Void
    private let previewSeed = BuddySeed.makeDefault()
    @AppStorage(AppLanguageMode.storageKey) private var languageModeRawValue = AppLanguageMode.system.rawValue

    private var text: AppText {
        AppText(language: (AppLanguageMode(rawValue: languageModeRawValue) ?? .system).resolvedLanguage)
    }

    var body: some View {
        OnboardingCenteredStage {
            VStack(spacing: 24) {
                BuddyAvatarView(seed: previewSeed, size: 144)

                VStack(spacing: 12) {
                    Image("MyBuddyLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 190)
                        .accessibilityLabel("MyBuddy")
                        .accessibilityIdentifier("onboarding.welcomeEyebrow")

                    Text(text.onboardingWelcomeTitle)
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(QuietNativeTheme.primaryText)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                        .accessibilityIdentifier("onboarding.welcomeTitle")

                    Text(text.onboardingWelcomeSubtitle)
                        .font(.subheadline)
                        .foregroundStyle(QuietNativeTheme.secondaryText)
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("onboarding.welcomeSubtitle")
                }

                OnboardingPrimaryButton(title: text.onboardingStart, action: onNext)
                    .accessibilityIdentifier("onboarding.welcomeStartButton")
            }
        }
    }
}

// MARK: - Privacy Step

struct PrivacyStepView: View {
    let onNext: () -> Void
    @State private var showPrivacyPolicy = false
    @State private var showTerms = false
    @AppStorage(AppLanguageMode.storageKey) private var languageModeRawValue = AppLanguageMode.system.rawValue

    private var text: AppText {
        AppText(language: (AppLanguageMode(rawValue: languageModeRawValue) ?? .system).resolvedLanguage)
    }

    var body: some View {
        OnboardingCenteredStage {
            VStack(spacing: 18) {
                VStack(spacing: 12) {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 52))
                        .foregroundStyle(QuietNativeTheme.accent)

                    Text(text.onboardingPrivacyTitle)
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(QuietNativeTheme.primaryText)
                        .multilineTextAlignment(.center)
                        .accessibilityIdentifier("onboarding.privacyTitle")

                    Text(text.onboardingPrivacySubtitle)
                        .font(.subheadline)
                        .foregroundStyle(QuietNativeTheme.secondaryText)
                        .multilineTextAlignment(.center)
                        .accessibilityIdentifier("onboarding.privacySubtitle")
                }

                VStack(spacing: 12) {
                    PrivacyRow(icon: "iphone", text: text.onboardingPrivacyDeviceRow)
                    PrivacyRow(icon: "lock.shield", text: text.onboardingPrivacyNoSendRow)
                    PrivacyRow(icon: "cpu", text: text.onboardingPrivacyAIRow)
                }

                VStack(spacing: 8) {
                    OnboardingPrimaryButton(title: text.onboardingAgreeStart, action: onNext)
                        .accessibilityIdentifier("onboarding.privacyNextButton")

                    HStack(spacing: 14) {
                        Button(text.privacyPolicy) { showPrivacyPolicy = true }
                            .accessibilityIdentifier("onboarding.privacyPolicyLink")
                        Text("/")
                            .foregroundStyle(QuietNativeTheme.secondaryText)
                        Button(text.termsOfService) { showTerms = true }
                            .accessibilityIdentifier("onboarding.termsLink")
                    }
                    .font(.footnote)
                    .foregroundStyle(QuietNativeTheme.accent)
                }
            }
        }
        .sheet(isPresented: $showPrivacyPolicy) {
            NavigationStack {
                LegalDocumentView(title: text.privacyPolicy, content: AppLegalContent.privacyPolicy(language: text.resolvedLanguage))
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button(text.close) { showPrivacyPolicy = false }
                        }
                    }
            }
        }
        .sheet(isPresented: $showTerms) {
            NavigationStack {
                LegalDocumentView(title: text.termsOfService, content: AppLegalContent.termsOfService(language: text.resolvedLanguage))
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button(text.close) { showTerms = false }
                        }
                    }
            }
        }
    }
}

struct PrivacyRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(QuietNativeTheme.accent)
                .frame(width: 36, height: 36)
                .background(QuietNativeTheme.accentSoft)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            Text(text)
                .font(.subheadline)
                .foregroundStyle(QuietNativeTheme.primaryText)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .layoutPriority(1)

            Spacer()
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 12)
        .quietNativeCard(cornerRadius: 22)
    }
}

// MARK: - Naming Step

struct NamingStepView: View {
    @Binding var name: String
    let onComplete: () -> Void
    @FocusState private var isFocused: Bool
    @AppStorage(AppLanguageMode.storageKey) private var languageModeRawValue = AppLanguageMode.system.rawValue

    private var text: AppText {
        AppText(language: (AppLanguageMode(rawValue: languageModeRawValue) ?? .system).resolvedLanguage)
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canContinue: Bool {
        !trimmedName.isEmpty
    }

    var body: some View {
        OnboardingCenteredStage {
            VStack(spacing: 22) {
                SilhouetteAvatar(size: 72)

                VStack(spacing: 10) {
                    Text(text.onboardingNamingTitle)
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(QuietNativeTheme.primaryText)
                        .accessibilityIdentifier("onboarding.namingTitle")

                }

                VStack(spacing: 10) {
                    TextField(text.onboardingBuddyNamePlaceholder, text: $name)
                        .font(.system(size: 26, weight: .semibold))
                        .multilineTextAlignment(.center)
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 18)
                        .background(QuietNativeTheme.backgroundWarm)
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .focused($isFocused)
                        .accessibilityIdentifier("onboarding.buddyNameField")

                    Text(canContinue ? text.onboardingNameReady : text.onboardingNameRequired)
                        .font(.caption)
                        .foregroundStyle(canContinue ? QuietNativeTheme.secondaryText : QuietNativeTheme.accent)
                }

                OnboardingPrimaryButton(
                    title: text.onboardingNameConfirm,
                    isDisabled: !canContinue,
                    action: onComplete
                )
                .accessibilityIdentifier("onboarding.namingConfirmButton")
            }
        }
        .onAppear { isFocused = true }
    }
}

// MARK: - LLM Waiting View

struct LLMWaitingView: View {
    let buddyName: String
    @AppStorage(AppLanguageMode.storageKey) private var languageModeRawValue = AppLanguageMode.system.rawValue

    private var text: AppText {
        AppText(language: (AppLanguageMode(rawValue: languageModeRawValue) ?? .system).resolvedLanguage)
    }

    var body: some View {
        OnboardingStatusStage(
            title: text.onboardingWaitingTitle(buddyName: buddyName),
            subtitle: text.onboardingWaitingSubtitle
        )
    }
}

// MARK: - Onboarding Chat View

struct OnboardingChatView: View {
    @ObservedObject var viewModel: OnboardingViewModel
    @FocusState private var isInputFocused: Bool
    @AppStorage(AppLanguageMode.storageKey) private var languageModeRawValue = AppLanguageMode.system.rawValue

    private var text: AppText {
        AppText(language: (AppLanguageMode(rawValue: languageModeRawValue) ?? .system).resolvedLanguage)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                SilhouetteAvatar(size: 40)

                VStack(alignment: .leading, spacing: 2) {
                    Text(viewModel.buddyName.isEmpty ? text.buddyDefaultName : viewModel.buddyName)
                        .font(.headline)
                        .foregroundStyle(QuietNativeTheme.primaryText)
                    Text(text.onboardingFirstChat)
                        .font(.caption)
                        .foregroundStyle(QuietNativeTheme.secondaryText)
                }

                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(
                Rectangle()
                    .fill(.white.opacity(0.55))
            )

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 16) {
                        HStack {
                            Text(text.onboardingShortAnswerHint)
                                .font(.footnote)
                                .foregroundStyle(QuietNativeTheme.secondaryText)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .quietNativeCard(cornerRadius: 18, fill: QuietNativeTheme.accentSoft)
                            Spacer()
                        }

                        ForEach(viewModel.chatMessages) { message in
                            if !message.text.isEmpty {
                                let isLast = message.id == viewModel.chatMessages.last?.id
                                OnboardingBubbleView(
                                    text: message.text,
                                    isFromBuddy: message.isFromBuddy,
                                    showSpinner: isLast && message.isFromBuddy && viewModel.isExtracting
                                )
                                .id(message.id)
                            }
                        }

                        if viewModel.isTyping && !(viewModel.chatMessages.last.map { $0.isFromBuddy && !$0.text.isEmpty } ?? false) {
                            OnboardingTypingIndicator()
                                .id("typing")
                        }

                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 16)
                    .padding(.bottom, 16)
                }
                .scrollIndicators(.hidden)
                .background(QuietNativeTheme.pageGradient.ignoresSafeArea())
                .safeAreaInset(edge: .bottom) {
                    VStack(spacing: 10) {
                        if viewModel.showConfirmButton {
                            OnboardingPrimaryButton(
                                title: text.onboardingEndChatButton(buddyName: viewModel.buddyName.isEmpty ? text.buddyDefaultName : viewModel.buddyName),
                                icon: "sparkles",
                                action: { viewModel.endChat() }
                            )
                            .disabled(!viewModel.canEndChat)
                            .accessibilityIdentifier("onboarding.endChatButton")
                        }

                        OnboardingInputComposer(
                            text: $viewModel.chatInputText,
                            canSend: canSend,
                            isTyping: viewModel.isTyping,
                            onSend: { viewModel.sendChatMessage() },
                            isInputFocused: $isInputFocused
                        )
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
                }
                .onChange(of: viewModel.chatMessages.count) {
                    withAnimation {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                }
                .onChange(of: viewModel.showConfirmButton) {
                    Task {
                        try? await Task.sleep(for: .milliseconds(100))
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
        }
    }

    private var canSend: Bool {
        !viewModel.chatInputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !viewModel.isTyping
    }
}

// MARK: - Onboarding Bubble

struct OnboardingBubbleView: View {
    let text: String
    let isFromBuddy: Bool
    var showSpinner: Bool = false

    var body: some View {
        if isFromBuddy {
            HStack(alignment: .top, spacing: 8) {
                SilhouetteAvatar(size: 32)

                VStack(alignment: .leading, spacing: 6) {
                    Text(text)
                        .font(.body)
                        .foregroundStyle(QuietNativeTheme.primaryText)
                        .multilineTextAlignment(.leading)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                        .layoutPriority(1)

                    if showSpinner {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
                .background(QuietNativeTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(QuietNativeTheme.line, lineWidth: 1)
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)
                .accessibilityIdentifier("onboarding.buddyMessageText")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            HStack {
                Spacer(minLength: 40)
                Text(text)
                    .font(.body)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.leading)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                    .layoutPriority(1)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(QuietNativeTheme.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .accessibilityIdentifier("onboarding.userMessageText")
            }
        }
    }
}

// MARK: - Onboarding Typing Indicator

struct OnboardingTypingIndicator: View {
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
            .padding(.leading, 40)

            Spacer()
        }
        .onAppear {
            dotCount = 0
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(400))
                dotCount = (dotCount + 1) % 3
            }
        }
    }
}

// MARK: - Extracting View

struct ExtractingView: View {
    let buddyName: String
    @AppStorage(AppLanguageMode.storageKey) private var languageModeRawValue = AppLanguageMode.system.rawValue

    private var text: AppText {
        AppText(language: (AppLanguageMode(rawValue: languageModeRawValue) ?? .system).resolvedLanguage)
    }

    var body: some View {
        OnboardingStatusStage(
            title: text.onboardingExtractingTitle(buddyName: buddyName),
            subtitle: text.onboardingExtractingSubtitle
        )
    }
}

// MARK: - Buddy Reveal View

struct BuddyRevealView: View {
    let seed: BuddySeed?
    let buddyName: String
    let greeting: String
    let onComplete: () -> Void
    let onRetry: () -> Void

    @State private var showAvatar = false
    @State private var showGreeting = false
    @State private var showTraits: [Bool] = [false, false, false, false]
    @AppStorage(AppLanguageMode.storageKey) private var languageModeRawValue = AppLanguageMode.system.rawValue

    private var text: AppText {
        AppText(language: (AppLanguageMode(rawValue: languageModeRawValue) ?? .system).resolvedLanguage)
    }

    var body: some View {
        OnboardingCenteredStage(maxWidth: 500, contentPadding: 20) {
            VStack(spacing: 18) {
                VStack(spacing: 10) {
                    Text(buddyName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(QuietNativeTheme.secondaryText)
                        .textCase(.uppercase)
                        .tracking(1.2)
                        .accessibilityIdentifier("onboarding.revealTitle")

                    if showGreeting {
                        Text(greeting)
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(QuietNativeTheme.primaryText)
                            .multilineTextAlignment(.center)
                            .lineSpacing(4)
                            .fixedSize(horizontal: false, vertical: true)
                            .transition(.opacity.combined(with: .scale(scale: 0.94)))
                            .accessibilityIdentifier("onboarding.revealGreeting")
                    }
                }
                .frame(maxWidth: 340)

                BuddyAvatarView(seed: seed, size: 128)
                    .opacity(showAvatar ? 1 : 0)
                    .scaleEffect(showAvatar ? 1 : 0.5)

                if let seed {
                    VStack(spacing: 8) {
                        if showTraits[0] {
                            OnboardingTraitRow(icon: "heart.fill", text: text.personaLabel(style: seed.personaStyle, custom: seed.personaStyleCustom))
                                .transition(.opacity.combined(with: .move(edge: .bottom)))
                        }
                        if showTraits[1] {
                            OnboardingTraitRow(icon: "person.wave.2.fill", text: text.distanceLabel(distance: seed.conversationDistance, custom: seed.conversationDistanceCustom))
                                .transition(.opacity.combined(with: .move(edge: .bottom)))
                        }
                        if showTraits[2] {
                            OnboardingTraitRow(icon: "book.fill", text: text.memoryLabel(memory: seed.memoryPreference, custom: seed.memoryPreferenceCustom))
                                .transition(.opacity.combined(with: .move(edge: .bottom)))
                        }
                        if showTraits[3] && !seed.customTraits.isEmpty {
                            OnboardingTraitRow(icon: "star.fill", text: seed.customTraits)
                                .transition(.opacity.combined(with: .move(edge: .bottom)))
                        }
                    }
                    .frame(maxWidth: 328)
                }

                if showTraits[3] {
                    VStack(spacing: 10) {
                        OnboardingPrimaryButton(title: text.onboardingRevealComplete, action: onComplete)
                            .accessibilityIdentifier("onboarding.revealCompleteButton")

                        Button(action: onRetry) {
                            Text(text.onboardingRetry)
                                .font(.subheadline)
                                .foregroundStyle(QuietNativeTheme.secondaryText)
                        }
                    }
                    .frame(maxWidth: 300)
                    .transition(.opacity)
                }
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
                showAvatar = true
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                withAnimation(.easeOut(duration: 0.3)) {
                    showGreeting = true
                }
            }

            for i in 0..<4 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0 + Double(i) * 0.3) {
                    withAnimation(.easeOut(duration: 0.3)) {
                        showTraits[i] = true
                    }
                }
            }
        }
    }
}

// MARK: - Complete

struct OnboardingCompleteView: View {
    @State private var showCheckmark = false
    @AppStorage(AppLanguageMode.storageKey) private var languageModeRawValue = AppLanguageMode.system.rawValue

    private var text: AppText {
        AppText(language: (AppLanguageMode(rawValue: languageModeRawValue) ?? .system).resolvedLanguage)
    }

    var body: some View {
        OnboardingCenteredStage(maxWidth: 420) {
            VStack(spacing: 24) {
                ZStack {
                    Circle()
                        .fill(Color.green.opacity(0.15))
                        .frame(width: 110, height: 110)
                    Image(systemName: "checkmark")
                        .font(.system(size: 42, weight: .bold))
                        .foregroundStyle(.green)
                        .scaleEffect(showCheckmark ? 1 : 0)
                }

                Text(text.onboardingCompleteTitle)
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(QuietNativeTheme.primaryText)

                Text(text.onboardingCompleteSubtitle)
                    .font(.subheadline)
                    .foregroundStyle(QuietNativeTheme.secondaryText)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) {
                showCheckmark = true
            }
        }
    }
}

// MARK: - Shared Components

private struct OnboardingCenteredStage<Content: View>: View {
    let maxWidth: CGFloat
    let contentPadding: CGFloat
    let content: Content

    init(maxWidth: CGFloat = 460, contentPadding: CGFloat = 20, @ViewBuilder content: () -> Content) {
        self.maxWidth = maxWidth
        self.contentPadding = contentPadding
        self.content = content()
    }

    var body: some View {
        VStack {
            content
        }
        .frame(maxWidth: maxWidth)
        .padding(contentPadding)
        .quietNativeCard(cornerRadius: 30)
        .padding(.horizontal, 20)
    }
}

private struct OnboardingStatusStage: View {
    let title: String
    let subtitle: String

    var body: some View {
        OnboardingCenteredStage(maxWidth: 420) {
            VStack(spacing: 24) {
                ZStack {
                    Circle()
                        .fill(QuietNativeTheme.accentSoft)
                        .frame(width: 120, height: 120)
                    ProgressView()
                        .scaleEffect(1.5)
                        .tint(QuietNativeTheme.accent)
                }

                Text(title)
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(QuietNativeTheme.primaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("onboarding.statusTitle")

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(QuietNativeTheme.secondaryText)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct OnboardingPrimaryButton: View {
    let title: String
    var icon: String? = nil
    var isDisabled = false
    let action: () -> Void

    var body: some View {
        Button {
            guard !isDisabled else { return }
            action()
        } label: {
            HStack(spacing: 10) {
                if let icon {
                    Image(systemName: icon)
                }
                Text(title)
                    .bold()
            }
            .font(.body)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(isDisabled ? QuietNativeTheme.secondaryText.opacity(0.35) : QuietNativeTheme.accent)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .contentShape(Rectangle())
        }
        .disabled(isDisabled)
    }
}

// MARK: - Choosing Appearance View

private struct ChoosingAppearanceView: View {
    @ObservedObject var viewModel: OnboardingViewModel

    @State private var selectedType: AppearanceType?
    @State private var selectedCandidateIndex: Int?
    @AppStorage(AppLanguageMode.storageKey) private var languageModeRawValue = AppLanguageMode.system.rawValue

    private var text: AppText {
        AppText(language: (AppLanguageMode(rawValue: languageModeRawValue) ?? .system).resolvedLanguage)
    }

    private let typeColumns = Array(repeating: GridItem(.flexible(minimum: 136), spacing: 16), count: 2)
    private let candidateColumns = Array(repeating: GridItem(.flexible(minimum: 96), spacing: 12), count: 3)

    private var buddyName: String {
        viewModel.buddyName.isEmpty ? text.buddyDefaultName : viewModel.buddyName
    }

    var body: some View {
        OnboardingCenteredStage(maxWidth: 420) {
            VStack(spacing: 24) {
                Text(title)
                    .font(.title2.bold())
                    .foregroundStyle(QuietNativeTheme.primaryText)

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(QuietNativeTheme.secondaryText)
                    .multilineTextAlignment(.center)

                if let selectedType {
                    candidateGrid(for: selectedType)
                } else {
                    typeSelection
                }
            }
        }
    }

    private var title: String {
        text.onboardingAppearanceTitle(buddyName: buddyName, hasSelectedType: selectedType != nil)
    }

    private var subtitle: String {
        text.onboardingAppearanceSubtitle(hasSelectedType: selectedType != nil)
    }

    private enum AppearanceType {
        case monster
        case ojisan

        var label: String {
            switch self {
            case .monster: return AppText.current.isEnglish ? "Monster" : "モンスター"
            case .ojisan: return AppText.current.isEnglish ? "Human" : "おじさん"
            }
        }
    }

    @ViewBuilder
    private var typeSelection: some View {
        LazyVGrid(columns: typeColumns, spacing: 16) {
            typeCard(type: .monster, seed: viewModel.monsterSeed)
            typeCard(type: .ojisan, seed: viewModel.ojisanSeed)
        }
    }

    @ViewBuilder
    private func typeCard(type: AppearanceType, seed: BuddySeed?) -> some View {
        let avatarSize: CGFloat = 120

        Button {
            selectedType = type
        } label: {
            VStack(spacing: 12) {
                AvatarSilhouette(seed: seed, size: avatarSize)
                .frame(width: avatarSize, height: avatarSize)

                Text(type.label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(QuietNativeTheme.secondaryText)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(type == .monster ? "onboarding.monsterSilhouette" : "onboarding.ojisanSilhouette")
    }

    @ViewBuilder
    private func candidateGrid(for type: AppearanceType) -> some View {
        let candidates = type == .monster ? viewModel.monsterCandidates : viewModel.ojisanCandidates

        VStack(spacing: 18) {
            LazyVGrid(columns: candidateColumns, spacing: 12) {
                ForEach(Array(candidates.enumerated()), id: \.offset) { index, seed in
                    candidateCard(seed: seed, index: index)
                }
            }
            .id(type)

            Button {
                selectedType = nil
                selectedCandidateIndex = nil
            } label: {
                Label(text.onboardingChooseTypeAgain, systemImage: "chevron.left")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(QuietNativeTheme.secondaryText)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(selectedCandidateIndex != nil)
        }
        .transaction { transaction in
            transaction.animation = nil
        }
    }

    @ViewBuilder
    private func candidateCard(seed: BuddySeed, index: Int) -> some View {
        let isSelected = selectedCandidateIndex == index
        let isOther = selectedCandidateIndex != nil && !isSelected
        let avatarSize: CGFloat = 96

        Button {
            guard selectedCandidateIndex == nil else { return }
            selectedCandidateIndex = index
            viewModel.selectAppearance(seed: seed)

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                viewModel.proceedAfterAppearanceReveal()
            }
        } label: {
            VStack(spacing: 10) {
                BuddyAvatarView(seed: seed, size: avatarSize, showAnimation: false)
                    .frame(width: avatarSize, height: avatarSize)

                VStack(spacing: 2) {
                    Text(text.appearanceDisplayName(for: seed))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(isSelected ? QuietNativeTheme.accent : QuietNativeTheme.primaryText)
                    Text(text.candidateLabel(index: index + 1))
                        .font(.caption2)
                        .foregroundStyle(QuietNativeTheme.secondaryText)
                }
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity)
            .frame(height: 148)
            .background(isSelected ? QuietNativeTheme.accentSoft : QuietNativeTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(isSelected ? QuietNativeTheme.accent.opacity(0.45) : QuietNativeTheme.line, lineWidth: 1)
            )
            .opacity(isOther ? 0.28 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(selectedCandidateIndex != nil)
        .accessibilityIdentifier("onboarding.appearanceCandidate.\(index + 1)")
    }
}

/// 実際の BuddyAvatarView をシルエット化して表示するコンポーネント
private struct AvatarSilhouette: View {
    let seed: BuddySeed?
    let size: CGFloat

    var body: some View {
        ZStack {
            // 実際のアバターを描画してからシルエット化
            BuddyAvatarView(seed: seed, size: size, showAnimation: false)
                .compositingGroup()
                .brightness(-1)       // 全ピクセルを黒に
                .opacity(0.18)        // 薄い影のように
            // 「？」をオーバーレイ
            Image(systemName: "questionmark")
                .font(.system(size: size * 0.25, weight: .bold))
                .foregroundStyle(QuietNativeTheme.secondaryText.opacity(0.4))
        }
        .frame(width: size, height: size)
    }
}

private struct SilhouetteAvatar: View {
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .fill(QuietNativeTheme.surfaceAlt)
                .frame(width: size, height: size)
            Image(systemName: "questionmark")
                .font(.system(size: size * 0.35, weight: .bold))
                .foregroundStyle(QuietNativeTheme.secondaryText.opacity(0.5))
        }
    }
}

private struct OnboardingTraitRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(QuietNativeTheme.accent)
                .frame(width: 24)
            Text(text)
                .font(.footnote)
                .foregroundStyle(QuietNativeTheme.primaryText)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .quietNativeCard(cornerRadius: 22)
    }
}

private struct OnboardingInputComposer: View {
    @Binding var text: String
    let canSend: Bool
    let isTyping: Bool
    let onSend: () -> Void
    let isInputFocused: FocusState<Bool>.Binding
    @AppStorage(AppLanguageMode.storageKey) private var languageModeRawValue = AppLanguageMode.system.rawValue

    private var appText: AppText {
        AppText(language: (AppLanguageMode(rawValue: languageModeRawValue) ?? .system).resolvedLanguage)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                TextField(appText.onboardingInputPlaceholder, text: $text, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...4)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(QuietNativeTheme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .focused(isInputFocused)
                    .accessibilityIdentifier("onboarding.chatInputField")

                Button(action: onSend) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 42, height: 42)
                        .background(canSend ? QuietNativeTheme.accent : QuietNativeTheme.secondaryText.opacity(0.4))
                        .clipShape(Circle())
                }
                .disabled(!canSend || isTyping)
                .accessibilityIdentifier("onboarding.sendButton")
            }
            .padding(14)
        }
        .quietNativeGlass()
    }
}
