import SwiftUI
import Combine
import Network
import UIKit

struct LaunchPreparationView: View {
    @AppStorage(AppLanguageMode.storageKey)
    private var appLanguageRawValue = AppLanguageMode.system.rawValue

    private var text: AppText {
        AppText(language: (AppLanguageMode(rawValue: appLanguageRawValue) ?? .system).resolvedLanguage)
    }

    var body: some View {
        ZStack {
            QuietNativeTheme.pageGradient
                .ignoresSafeArea()

            VStack(spacing: 18) {
                Image("MyBuddyLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 180, height: 46)
                    .accessibilityLabel("MyBuddy")

                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(QuietNativeTheme.accent)
                    .scaleEffect(1.2)

                Text(text.launchPreparingTitle)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(QuietNativeTheme.primaryText)

                Text(text.launchPreparingMessage)
                    .font(.subheadline)
                    .foregroundStyle(QuietNativeTheme.secondaryText)
                    .multilineTextAlignment(.center)
            }
            .padding(28)
        }
    }
}

struct ModelSetupView: View {
    @EnvironmentObject private var appState: AppState
    @AppStorage(AppLanguageMode.storageKey)
    private var appLanguageRawValue = AppLanguageMode.system.rawValue
    @StateObject private var networkConnectivity = NetworkConnectivityObserver()
    @State private var didDeclineDownload = false
    @State private var showWifiRequiredAlert = false

    private var text: AppText {
        AppText(language: (AppLanguageMode(rawValue: appLanguageRawValue) ?? .system).resolvedLanguage)
    }

    private var setupState: ModelSetupState {
        appState.modelSetupState
    }

    private var requirement: ModelSetupRequirement {
        setupState.requirement ?? ModelSetupRequirement(
            assetNames: [],
            totalBytes: 0,
            requiredFreeSpaceBytes: 0,
            downloadConfigured: false,
            missingAssetNames: [],
            invalidAssetNames: []
        )
    }

    private var progress: ModelDownloadProgressSnapshot? {
        setupState.progress
    }

    private var errorMessage: String? {
        setupState.errorMessage
    }

    private var isDownloading: Bool {
        if case .downloading = setupState {
            return true
        }
        return false
    }

    private var primaryButtonTitle: String {
        switch setupState {
        case .downloading:
            return text.modelSetupDownloadingButton
        case .failed:
            return text.modelSetupRetry
        case .setupRequired:
            return requirement.downloadConfigured ? text.modelSetupStartDownload(size: downloadSizeText) : text.modelSetupPreparing
        case .checking, .ready:
            return text.modelSetupStartDownload(size: downloadSizeText)
        }
    }

    private var downloadSizeText: String {
        text.approximateSize(byteText(requirement.totalBytes))
    }

    var body: some View {
        ZStack {
            setupLanding

            Color.black.opacity(0.16)
                .ignoresSafeArea()

            VStack {
                Spacer(minLength: 28)
                setupModal
                Spacer(minLength: 28)
            }
            .padding(.horizontal, 18)
        }
        .accessibilityIdentifier("modelSetup.screen")
        .onAppear {
            updateIdleTimerDisabled(isDownloading)
        }
        .onChange(of: isDownloading) { _, newValue in
            updateIdleTimerDisabled(newValue)
        }
        .onDisappear {
            updateIdleTimerDisabled(false)
        }
        .alert(text.modelSetupWifiAlertTitle, isPresented: $showWifiRequiredAlert) {
            Button(text.modelSetupWifiAlertCancel, role: .cancel) {}
            Button(text.modelSetupWifiAlertContinue) {
                beginModelSetup()
            }
        } message: {
            Text(text.modelSetupWifiAlertMessage)
        }
    }

    private var setupLanding: some View {
        ZStack {
            QuietNativeTheme.pageGradient
                .ignoresSafeArea()

            Circle()
                .fill(QuietNativeTheme.accentSoft.opacity(0.75))
                .frame(width: 300, height: 300)
                .blur(radius: 20)
                .offset(x: 130, y: -260)

            Circle()
                .fill(Color(red: 0.72, green: 0.84, blue: 0.60).opacity(0.22))
                .frame(width: 280, height: 280)
                .blur(radius: 28)
                .offset(x: -140, y: 250)

            VStack(spacing: 24) {
                VStack(spacing: 12) {
                    Image("MyBuddyLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 210, height: 54)
                        .accessibilityLabel("MyBuddy")

                    Text(text.modelSetupHeroTitle)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(QuietNativeTheme.primaryText)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 42)

                BuddyAvatarView(seed: .makeDefault(), size: 150, showAnimation: true)
                    .padding(.top, 4)

                Spacer()

                BuddyMarqueeView()
                    .frame(height: 112)
                    .padding(.bottom, 18)
            }
            .padding(.horizontal, 24)
        }
    }

    private var setupModal: some View {
        VStack(spacing: 20) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(QuietNativeTheme.line)
                .frame(width: 42, height: 5)
                .opacity(0.8)

            VStack(spacing: 8) {
                Text(text.modelSetupEyebrow)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(QuietNativeTheme.accent)
                    .tracking(1.8)

                Text(text.modelSetupTitle)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(QuietNativeTheme.primaryText)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("modelSetup.title")

                Text(text.modelSetupSubtitle)
                    .font(.subheadline)
                    .foregroundStyle(QuietNativeTheme.secondaryText)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }

            VStack(spacing: 12) {
                setupSummaryRow(icon: "iphone", text: text.modelSetupOnDeviceRow)
                setupSummaryRow(icon: "externaldrive", text: text.modelSetupSizeRow(size: downloadSizeText))
                setupSummaryRow(icon: "wifi", text: text.modelSetupWifiRow)
                setupSummaryRow(icon: "lock.shield", text: text.modelSetupOfflineRow)
            }

            if isDownloading || progress != nil {
                progressSection(progress)
            }

            if let errorMessage {
                errorCard(errorMessage)
            }

            if didDeclineDownload && !isDownloading {
                declineNotice
            }

            actionSection
        }
        .padding(.horizontal, 22)
        .padding(.top, 14)
        .padding(.bottom, 22)
        .frame(maxWidth: 430)
        .background(.ultraThinMaterial)
        .overlay(
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .stroke(Color.white.opacity(0.68), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
        .shadow(color: Color.black.opacity(0.14), radius: 28, y: 16)
    }

    private func setupSummaryRow(icon: String, text: String) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(QuietNativeTheme.accent)
                .frame(width: 34, height: 34)
                .background(QuietNativeTheme.accentSoft)
                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))

            Text(text)
                .font(.subheadline)
                .foregroundStyle(QuietNativeTheme.primaryText)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
    }

    private func progressSection(_ progress: ModelDownloadProgressSnapshot?) -> some View {
        let fraction = progress?.overallFractionCompleted ?? 0

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(text.modelSetupDownloadingTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(QuietNativeTheme.primaryText)
                Spacer()
                Text("\(Int(fraction * 100))%")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(QuietNativeTheme.accent)
            }

            ProgressView(value: fraction, total: 1)
                .tint(QuietNativeTheme.accent)
                .accessibilityIdentifier("modelSetup.overallProgress")

            if let progress {
                Text("\(byteText(progress.totalReceivedBytes)) / \(byteText(progress.totalExpectedBytes))")
                    .font(.caption)
                    .foregroundStyle(QuietNativeTheme.secondaryText)
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.58))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func errorCard(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(text.modelSetupErrorTitle, systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.red)

            Text(message)
                .font(.footnote)
                .foregroundStyle(QuietNativeTheme.primaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(Color.red.opacity(0.08))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.red.opacity(0.18), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var declineNotice: some View {
        Text(text.modelSetupDeclineNotice)
            .font(.footnote)
            .foregroundStyle(QuietNativeTheme.secondaryText)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 6)
            .accessibilityIdentifier("modelSetup.declineNotice")
    }

    private var actionSection: some View {
        VStack(alignment: .center, spacing: 10) {
            Button {
                beginModelSetupIfWifiAvailable()
            } label: {
                HStack(spacing: 10) {
                    if isDownloading {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: "arrow.down.circle")
                    }
                    Text(primaryButtonTitle)
                        .fontWeight(.semibold)
                }
                .font(.body)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(requirement.downloadConfigured ? QuietNativeTheme.accent : QuietNativeTheme.secondaryText.opacity(0.55))
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            }
            .disabled(isDownloading || !requirement.downloadConfigured)
            .accessibilityIdentifier("modelSetup.primaryButton")

            Button {
                didDeclineDownload = true
            } label: {
                Text(text.modelSetupNotNow)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(QuietNativeTheme.secondaryText)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
            }
            .disabled(isDownloading)
            .accessibilityIdentifier("modelSetup.declineButton")

            Text(text.modelSetupWifiHint)
                .font(.footnote)
                .foregroundStyle(QuietNativeTheme.secondaryText)
                .multilineTextAlignment(.center)
        }
    }

    private func beginModelSetupIfWifiAvailable() {
        guard networkConnectivity.isConnectedToWiFi else {
            showWifiRequiredAlert = true
            return
        }

        beginModelSetup()
    }

    private func beginModelSetup() {
        Task {
            didDeclineDownload = false
            if case .failed = setupState {
                await appState.retryModelSetup()
            } else {
                await appState.startModelSetup()
            }
        }
    }

    private func updateIdleTimerDisabled(_ disabled: Bool) {
        guard UIApplication.shared.isIdleTimerDisabled != disabled else { return }
        UIApplication.shared.isIdleTimerDisabled = disabled
    }

    private func byteText(_ bytes: Int64) -> String {
        guard bytes > 0 else { return text.notConfigured }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

@MainActor
private final class NetworkConnectivityObserver: ObservableObject {
    @Published var isConnectedToWiFi = false

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "mybuddy.network.connectivity")

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let isConnectedToWiFi = path.status == .satisfied && path.usesInterfaceType(.wifi)
            Task { @MainActor [weak self] in
                self?.isConnectedToWiFi = isConnectedToWiFi
            }
        }
        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
    }
}

private struct BuddyMarqueeView: View {
    private struct MarqueeBuddy: Identifiable {
        enum Kind {
            case monster
            case ojisan
            case fish
        }

        let id: Int
        let kind: Kind
        let seed: BuddySeed
        let scale: CGFloat
        let yOffset: CGFloat
        let rotation: Double
    }

    // モンスター多めにしつつ、魚・おじさん全種類も混ぜた固定シャッフル。
    private static let buddies: [MarqueeBuddy] = [
        MarqueeBuddy(
            id: 0,
            kind: .monster,
            seed: .makeDefault(),
            scale: 1.04,
            yOffset: 0,
            rotation: -4
        ),
        MarqueeBuddy(
            id: 18,
            kind: .fish,
            seed: fish(body: "fish_round", eye: "sparkle", mouth: "open", palette: "cool"),
            scale: 0.92,
            yOffset: 8,
            rotation: 6
        ),
        MarqueeBuddy(
            id: 12,
            kind: .ojisan,
            seed: ojisan("ojisan_baldglasses"),
            scale: 0.92,
            yOffset: 13,
            rotation: 4
        ),
        MarqueeBuddy(
            id: 1,
            kind: .monster,
            seed: monster(body: "fluffy", eye: "happy", ear: "bunny", mouth: "smile", palette: "warm"),
            scale: 0.94,
            yOffset: 10,
            rotation: 6
        ),
        MarqueeBuddy(
            id: 19,
            kind: .fish,
            seed: fish(body: "fish_long", eye: "big", mouth: "smile", palette: "warm"),
            scale: 1.10,
            yOffset: -3,
            rotation: -3
        ),
        MarqueeBuddy(
            id: 13,
            kind: .ojisan,
            seed: ojisan("ojisan_combover"),
            scale: 0.98,
            yOffset: 6,
            rotation: -3
        ),
        MarqueeBuddy(
            id: 2,
            kind: .monster,
            seed: monster(body: "chubby", eye: "big", ear: "cat", mouth: "grin", palette: "earth"),
            scale: 1.08,
            yOffset: -2,
            rotation: -2
        ),
        MarqueeBuddy(
            id: 20,
            kind: .fish,
            seed: fish(body: "fish_yamame", eye: "happy", mouth: "smile", palette: "earth"),
            scale: 0.98,
            yOffset: 9,
            rotation: 4
        ),
        MarqueeBuddy(
            id: 14,
            kind: .ojisan,
            seed: ojisan("ojisan_mustache"),
            scale: 0.92,
            yOffset: 14,
            rotation: -5
        ),
        MarqueeBuddy(
            id: 3,
            kind: .monster,
            seed: monster(body: "round", eye: "wink", ear: "horns", mouth: "fangs", palette: "cool"),
            scale: 0.96,
            yOffset: 8,
            rotation: 5
        ),
        MarqueeBuddy(
            id: 21,
            kind: .fish,
            seed: fish(body: "fish_clownfish", eye: "sparkle", mouth: "open", palette: "warm"),
            scale: 0.86,
            yOffset: 16,
            rotation: -6
        ),
        MarqueeBuddy(
            id: 15,
            kind: .ojisan,
            seed: ojisan("ojisan_charai"),
            scale: 0.96,
            yOffset: 8,
            rotation: 5
        ),
        MarqueeBuddy(
            id: 4,
            kind: .monster,
            seed: monster(body: "fluffy", eye: "sleepy", ear: "droopy", mouth: "cat", palette: "pastel"),
            scale: 0.88,
            yOffset: 13,
            rotation: -7
        ),
        MarqueeBuddy(
            id: 22,
            kind: .fish,
            seed: fish(body: "fish_lionfish", eye: "wink", mouth: "pout", palette: "earth"),
            scale: 1.00,
            yOffset: 7,
            rotation: 5
        ),
        MarqueeBuddy(
            id: 16,
            kind: .ojisan,
            seed: ojisan("ojisan_keibu"),
            scale: 0.94,
            yOffset: 12,
            rotation: -4
        ),
        MarqueeBuddy(
            id: 5,
            kind: .monster,
            seed: monster(body: "chubby", eye: "sparkle", ear: "devil", mouth: "open", palette: "warm"),
            scale: 1.02,
            yOffset: 2,
            rotation: 3
        ),
        MarqueeBuddy(
            id: 23,
            kind: .fish,
            seed: fish(body: "fish_round", eye: "heart", mouth: "smile", palette: "pastel"),
            scale: 0.88,
            yOffset: 15,
            rotation: -4
        ),
        MarqueeBuddy(
            id: 17,
            kind: .ojisan,
            seed: ojisan("ojisan_timid"),
            scale: 0.90,
            yOffset: 12,
            rotation: 3
        ),
        MarqueeBuddy(
            id: 6,
            kind: .monster,
            seed: monster(body: "round", eye: "star", ear: "bat", mouth: "tongue", palette: "pastel"),
            scale: 0.92,
            yOffset: 14,
            rotation: -5
        ),
        MarqueeBuddy(
            id: 24,
            kind: .fish,
            seed: fish(body: "fish_clownfish", eye: "big", mouth: "smile", palette: "cool"),
            scale: 0.90,
            yOffset: 13,
            rotation: 4
        ),
        MarqueeBuddy(
            id: 7,
            kind: .monster,
            seed: monster(body: "fluffy", eye: "heart", ear: "big_round", mouth: "smile", palette: "earth"),
            scale: 1.00,
            yOffset: 5,
            rotation: 4
        ),
        MarqueeBuddy(
            id: 25,
            kind: .fish,
            seed: fish(body: "fish_yamame", eye: "sleepy", mouth: "flat", palette: "pastel"),
            scale: 0.98,
            yOffset: 6,
            rotation: -3
        ),
        MarqueeBuddy(
            id: 8,
            kind: .monster,
            seed: monster(body: "chubby", eye: "dizzy", ear: "floppy", mouth: "wavy", palette: "cool"),
            scale: 0.90,
            yOffset: 15,
            rotation: 7
        ),
        MarqueeBuddy(
            id: 26,
            kind: .fish,
            seed: fish(body: "fish_long", eye: "sparkle", mouth: "open", palette: "earth"),
            scale: 1.08,
            yOffset: -2,
            rotation: 2
        ),
        MarqueeBuddy(
            id: 9,
            kind: .monster,
            seed: monster(body: "round", eye: "dot", ear: "pointed", mouth: "flat", palette: "warm"),
            scale: 0.98,
            yOffset: 4,
            rotation: -2
        ),
        MarqueeBuddy(
            id: 27,
            kind: .fish,
            seed: fish(body: "fish_lionfish", eye: "angry", mouth: "open", palette: "warm"),
            scale: 0.95,
            yOffset: 10,
            rotation: -5
        ),
        MarqueeBuddy(
            id: 10,
            kind: .monster,
            seed: monster(body: "fluffy", eye: "big", ear: "cat", mouth: "open", palette: "cool"),
            scale: 1.06,
            yOffset: -1,
            rotation: 3
        ),
        MarqueeBuddy(
            id: 28,
            kind: .fish,
            seed: fish(body: "fish_round", eye: "dot", mouth: "wavy", palette: "earth"),
            scale: 0.92,
            yOffset: 13,
            rotation: 6
        ),
        MarqueeBuddy(
            id: 11,
            kind: .monster,
            seed: monster(body: "chubby", eye: "happy", ear: "bunny", mouth: "grin", palette: "pastel"),
            scale: 0.94,
            yOffset: 10,
            rotation: -6
        ),
        MarqueeBuddy(
            id: 29,
            kind: .fish,
            seed: fish(body: "fish_yamame", eye: "star", mouth: "smile", palette: "cool"),
            scale: 0.96,
            yOffset: 8,
            rotation: 5
        ),
        MarqueeBuddy(
            id: 30,
            kind: .monster,
            seed: monster(body: "round", eye: "happy", ear: "bunny", mouth: "open", palette: "warm"),
            scale: 1.03,
            yOffset: 1,
            rotation: -4
        ),
        MarqueeBuddy(
            id: 31,
            kind: .monster,
            seed: monster(body: "fluffy", eye: "wink", ear: "horns", mouth: "grin", palette: "earth"),
            scale: 0.96,
            yOffset: 9,
            rotation: 6
        ),
        MarqueeBuddy(
            id: 32,
            kind: .fish,
            seed: fish(body: "fish_long", eye: "happy", mouth: "open", palette: "cool"),
            scale: 1.04,
            yOffset: 2,
            rotation: -3
        ),
        MarqueeBuddy(
            id: 33,
            kind: .monster,
            seed: monster(body: "chubby", eye: "sparkle", ear: "cat", mouth: "smile", palette: "pastel"),
            scale: 1.02,
            yOffset: 4,
            rotation: 3
        ),
        MarqueeBuddy(
            id: 34,
            kind: .ojisan,
            seed: ojisan("ojisan_keibu"),
            scale: 0.94,
            yOffset: 12,
            rotation: 4
        ),
        MarqueeBuddy(
            id: 35,
            kind: .monster,
            seed: monster(body: "round", eye: "dot", ear: "floppy", mouth: "smile", palette: "cool"),
            scale: 0.98,
            yOffset: 5,
            rotation: -2
        ),
        MarqueeBuddy(
            id: 36,
            kind: .monster,
            seed: monster(body: "fluffy", eye: "big", ear: "devil", mouth: "fangs", palette: "warm"),
            scale: 1.05,
            yOffset: -1,
            rotation: 5
        ),
        MarqueeBuddy(
            id: 37,
            kind: .fish,
            seed: fish(body: "fish_clownfish", eye: "star", mouth: "smile", palette: "earth"),
            scale: 0.88,
            yOffset: 15,
            rotation: 6
        ),
        MarqueeBuddy(
            id: 38,
            kind: .monster,
            seed: monster(body: "chubby", eye: "sleepy", ear: "droopy", mouth: "cat", palette: "earth"),
            scale: 0.93,
            yOffset: 12,
            rotation: -6
        ),
        MarqueeBuddy(
            id: 39,
            kind: .ojisan,
            seed: ojisan("ojisan_timid"),
            scale: 0.90,
            yOffset: 13,
            rotation: -3
        ),
        MarqueeBuddy(
            id: 40,
            kind: .monster,
            seed: monster(body: "round", eye: "heart", ear: "big_round", mouth: "tongue", palette: "pastel"),
            scale: 0.94,
            yOffset: 11,
            rotation: 4
        ),
        MarqueeBuddy(
            id: 41,
            kind: .monster,
            seed: monster(body: "fluffy", eye: "sparkle", ear: "bat", mouth: "open", palette: "cool"),
            scale: 1.08,
            yOffset: -2,
            rotation: -4
        ),
        MarqueeBuddy(
            id: 42,
            kind: .fish,
            seed: fish(body: "fish_lionfish", eye: "big", mouth: "pout", palette: "pastel"),
            scale: 0.96,
            yOffset: 10,
            rotation: -5
        ),
        MarqueeBuddy(
            id: 43,
            kind: .monster,
            seed: monster(body: "chubby", eye: "happy", ear: "horns", mouth: "grin", palette: "warm"),
            scale: 1.00,
            yOffset: 3,
            rotation: 2
        ),
        MarqueeBuddy(
            id: 44,
            kind: .monster,
            seed: monster(body: "round", eye: "wink", ear: "cat", mouth: "smile", palette: "earth"),
            scale: 0.97,
            yOffset: 7,
            rotation: -3
        )
    ]

    var body: some View {
        TimelineView(.animation) { timeline in
            GeometryReader { proxy in
                let itemWidth: CGFloat = 82
                let spacing: CGFloat = 24
                let contentWidth = CGFloat(Self.buddies.count) * (itemWidth + spacing)
                let elapsed = timeline.date.timeIntervalSinceReferenceDate
                let offset = -CGFloat(elapsed.truncatingRemainder(dividingBy: 78) / 78) * contentWidth

                HStack(spacing: spacing) {
                    marqueeContent(itemWidth: itemWidth)
                    marqueeContent(itemWidth: itemWidth)
                }
                .offset(x: offset + proxy.size.width * 0.12)
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .leading)
                .mask(
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .black, location: 0.10),
                            .init(color: .black, location: 0.90),
                            .init(color: .clear, location: 1)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func marqueeContent(itemWidth: CGFloat) -> some View {
        ForEach(Self.buddies) { buddy in
            BuddyAvatarView(seed: buddy.seed, size: itemWidth * buddy.scale, showAnimation: true)
                .rotationEffect(.degrees(buddy.rotation))
                .offset(y: buddy.yOffset)
                .frame(width: itemWidth, height: itemWidth + 24)
                .padding(.vertical, 8)
        }
    }

    private static func monster(
        body: String,
        eye: String,
        ear: String,
        mouth: String,
        palette: String
    ) -> BuddySeed {
        seed(characterType: "monster", body: body, eye: eye, ear: ear, mouth: mouth, palette: palette)
    }

    private static func fish(
        body: String,
        eye: String,
        mouth: String,
        palette: String
    ) -> BuddySeed {
        seed(characterType: "fish", body: body, eye: eye, ear: "round", mouth: mouth, palette: palette)
    }

    private static func ojisan(_ variant: String) -> BuddySeed {
        switch variant {
        case "ojisan_combover":
            return seed(characterType: "ojisan", body: variant, eye: "sparkle", ear: "round", mouth: "smile", palette: "warm")
        case "ojisan_mustache":
            return seed(characterType: "ojisan", body: variant, eye: "dot", ear: "round", mouth: "grin", palette: "earth")
        case "ojisan_charai":
            return seed(characterType: "ojisan", body: variant, eye: "wink", ear: "round", mouth: "grin", palette: "cool")
        case "ojisan_keibu":
            return seed(characterType: "ojisan", body: variant, eye: "sparkle", ear: "round", mouth: "flat", palette: "warm")
        case "ojisan_timid":
            return seed(characterType: "ojisan", body: variant, eye: "big", ear: "round", mouth: "smile", palette: "pastel")
        default:
            return seed(characterType: "ojisan", body: "ojisan_baldglasses", eye: "dot", ear: "round", mouth: "smile", palette: "warm")
        }
    }

    private static func seed(
        characterType: String,
        body: String,
        eye: String,
        ear: String,
        mouth: String,
        palette: String
    ) -> BuddySeed {
        BuddySeed(
            characterType: characterType,
            bodyId: body,
            eyeId: eye,
            earId: ear,
            mouthId: mouth,
            paletteId: palette,
            accentIds: [],
            personaStyle: .gentle,
            conversationDistance: .casual,
            memoryPreference: .balanced,
            personalityNotes: "",
            customTraits: "",
            personaStyleCustom: "",
            conversationDistanceCustom: "",
            memoryPreferenceCustom: "",
            roomThemeId: "room_default"
        )
    }
}
