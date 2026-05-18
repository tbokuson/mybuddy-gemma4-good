import Foundation
import SwiftUI
import Combine

@MainActor
final class AppState: ObservableObject {
    @Published var llmStatus: LLMStatus = .notLoaded
    @Published var errorMessage: String?
    @Published var modelSetupState: ModelSetupState = .checking

    private(set) var llmService: any LLMServiceProtocol
    private let modelDeliveryController: any ModelDeliveryControlling
    private let shouldAutoInitializeLLM: Bool
    private var hasPreparedLaunch = false
    private var isPreparingLaunch = false
    private var isDownloadingModelAssets = false
    private var latestModelDownloadProgress: ModelDownloadProgressSnapshot?
    private var shouldResumeInterruptedModelSetup = false
    private var interruptedModelSetupRetryCount = 0
    private var interruptedModelSetupRetryTask: Task<Void, Never>?
    private var currentScenePhase: ScenePhase = .active

    private let maxInterruptedModelSetupRetries = 6
    private let interruptedModelSetupRetryDelayNanoseconds: UInt64 = 1_500_000_000

    enum LLMStatus: Equatable {
        case notLoaded
        case loading
        case loaded
        case error(String)
    }

    init(
        llmService: (any LLMServiceProtocol)? = nil,
        modelDeliveryController: (any ModelDeliveryControlling)? = nil,
        shouldAutoInitializeLLM: Bool? = nil
    ) {
        self.llmService = llmService ?? LLMServiceFactory.makeFromEnvironment()
        self.modelDeliveryController = modelDeliveryController ?? ModelDeliveryController()
        self.shouldAutoInitializeLLM = shouldAutoInitializeLLM ?? AppEnvironment.shouldAutoInitializeLLM
    }

    func prepareForLaunch() async {
        guard !isPreparingLaunch else { return }
        guard !hasPreparedLaunch || modelSetupState != .ready || llmStatus == .notLoaded else { return }

        isPreparingLaunch = true
        defer {
            isPreparingLaunch = false
            hasPreparedLaunch = true
        }

        errorMessage = nil
        llmStatus = .notLoaded
        modelSetupState = .checking

        if !llmService.requiresLocalModelAssets {
            modelSetupState = .ready
            if shouldAutoInitializeLLM {
                await initializeLLM()
            }
            return
        }

        let requirement = currentModelSetupRequirement()

        if AppEnvironment.shouldForceModelSetup, let requirement {
            modelSetupState = .setupRequired(requirement)
            return
        }

        if let report = modelDeliveryController.assessAvailability() {
            if report.isReady {
                modelSetupState = .ready
                if shouldAutoInitializeLLM {
                    await initializeLLM()
                }
            } else {
                modelSetupState = .setupRequired(report.setupRequirement)
            }
            return
        }

        let fallbackRequirement = requirement ?? ModelSetupRequirement(
            assetNames: [],
            totalBytes: 0,
            requiredFreeSpaceBytes: 0,
            downloadConfigured: false,
            missingAssetNames: [],
            invalidAssetNames: []
        )
        let message = localizedMessage(for: ModelDeliveryError.manifestMissing)
        modelSetupState = .failed(fallbackRequirement, message)
        errorMessage = message
    }

    func initializeLLM() async {
        llmStatus = .loading

        do {
            try await llmService.loadModel()
            self.llmStatus = .loaded
            self.errorMessage = nil
        } catch {
            #if DEBUG
            print("LLM読み込み失敗: \(error.localizedDescription)")
            #endif
            handleLLMInitializationError(error)
        }
    }

    func startModelSetup() async {
        guard !isDownloadingModelAssets else { return }
        guard llmService.requiresLocalModelAssets else {
            modelSetupState = .ready
            return
        }

        let requirement = currentModelSetupRequirement() ?? ModelSetupRequirement(
            assetNames: [],
            totalBytes: 0,
            requiredFreeSpaceBytes: 0,
            downloadConfigured: false,
            missingAssetNames: [],
            invalidAssetNames: []
        )

        isDownloadingModelAssets = true
        shouldResumeInterruptedModelSetup = false
        interruptedModelSetupRetryTask?.cancel()
        if latestModelDownloadProgress?.totalReceivedBytes == latestModelDownloadProgress?.totalExpectedBytes {
            latestModelDownloadProgress = nil
        }
        errorMessage = nil
        llmStatus = .notLoaded
        modelSetupState = .downloading(requirement, latestModelDownloadProgress)

        do {
            let report = try await modelDeliveryController.downloadRequiredAssets { [weak self] snapshot in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    let previousReceivedBytes = self.latestModelDownloadProgress?.totalReceivedBytes ?? -1
                    if snapshot.totalReceivedBytes > previousReceivedBytes {
                        self.interruptedModelSetupRetryCount = 0
                    }
                    self.latestModelDownloadProgress = snapshot
                    self.modelSetupState = .downloading(requirement, snapshot)
                }
            }

            guard report.isReady else {
                throw ModelDeliveryError.validationFailed(
                    AppLanguageMode.currentResolved == .english
                        ? "Required model verification did not complete."
                        : "必須モデルの検証が完了しませんでした。"
                )
            }

            let readyRequirement = report.setupRequirement
            modelSetupState = .ready
            hasPreparedLaunch = true
            isDownloadingModelAssets = false
            latestModelDownloadProgress = nil
            shouldResumeInterruptedModelSetup = false
            interruptedModelSetupRetryCount = 0

            if shouldAutoInitializeLLM {
                await initializeLLM()
            } else {
                llmStatus = .notLoaded
            }

            if case .error(let message) = llmStatus {
                modelSetupState = .failed(readyRequirement, message)
            }
        } catch {
            isDownloadingModelAssets = false
            if shouldKeepModelSetupWaiting(for: error), interruptedModelSetupRetryCount < maxInterruptedModelSetupRetries {
                interruptedModelSetupRetryCount += 1
                shouldResumeInterruptedModelSetup = true
                errorMessage = nil
                modelSetupState = .downloading(requirement, latestModelDownloadProgress)
                if currentScenePhase == .active {
                    await startModelSetup()
                } else {
                    scheduleInterruptedModelSetupRetryIfNeeded()
                }
                return
            }

            let message = localizedMessage(for: error)
            modelSetupState = .failed(requirement, message)
            errorMessage = message
        }
    }

    func retryModelSetup() async {
        await startModelSetup()
    }

    func preserveModelSetupAfterUserDataReset() {
        interruptedModelSetupRetryTask?.cancel()
        shouldResumeInterruptedModelSetup = false
        interruptedModelSetupRetryCount = 0
        latestModelDownloadProgress = nil
        errorMessage = nil

        if modelSetupState == .ready || llmStatus == .loaded {
            modelSetupState = .ready
            hasPreparedLaunch = true
            return
        }

        guard llmService.requiresLocalModelAssets else {
            modelSetupState = .ready
            hasPreparedLaunch = true
            return
        }

        if let report = modelDeliveryController.assessAvailability(), report.isReady {
            modelSetupState = .ready
            hasPreparedLaunch = true
        }
    }

    var isLLMReady: Bool {
        llmStatus == .loaded
    }

    var llmBackendDescription: String {
        llmService.backendDescription
    }

    var availableDiskSpaceBytes: Int64? {
        modelDeliveryController.availableDiskSpaceBytes()
    }

    func handleScenePhaseChange(_ scenePhase: ScenePhase) {
        currentScenePhase = scenePhase
        if scenePhase == .active {
            scheduleInterruptedModelSetupRetryIfNeeded(delayNanoseconds: 0)
            return
        }

        if scenePhase == .background {
            llmService.releaseBackgroundResources()
        }
    }

    private func scheduleInterruptedModelSetupRetryIfNeeded(delayNanoseconds: UInt64? = nil) {
        guard shouldResumeInterruptedModelSetup,
              !isDownloadingModelAssets,
              currentScenePhase == .active else { return }

        interruptedModelSetupRetryTask?.cancel()
        let delay = delayNanoseconds ?? interruptedModelSetupRetryDelayNanoseconds
        interruptedModelSetupRetryTask = Task { [weak self] in
            if delay > 0 {
                try? await Task.sleep(nanoseconds: delay)
            }
            guard !Task.isCancelled else { return }
            await self?.resumeInterruptedModelSetupIfNeeded()
        }
    }

    private func resumeInterruptedModelSetupIfNeeded() async {
        guard shouldResumeInterruptedModelSetup,
              !isDownloadingModelAssets,
              currentScenePhase == .active else { return }

        await startModelSetup()
    }

    private func currentModelSetupRequirement() -> ModelSetupRequirement? {
        if let report = modelDeliveryController.assessAvailability() {
            return report.setupRequirement
        }
        return modelDeliveryController.manifest?.setupRequirement
    }

    private func handleLLMInitializationError(_ error: Error) {
        if let llmError = error as? LLMError,
           case .modelSetupRequired(let requirement) = llmError {
            llmStatus = .notLoaded
            modelSetupState = .setupRequired(requirement)
            errorMessage = llmError.localizedDescription
            return
        }

        let message = localizedMessage(for: error)
        llmStatus = .error(message)
        errorMessage = message
    }

    private func localizedMessage(for error: Error) -> String {
        if let localizedError = error as? LocalizedError,
           let description = localizedError.errorDescription {
            return description
        }
        return error.localizedDescription
    }

    private func shouldKeepModelSetupWaiting(for error: Error) -> Bool {
        if let deliveryError = error as? ModelDeliveryError,
           case .network = deliveryError {
            return true
        }

        guard let urlError = error as? URLError else { return false }
        switch urlError.code {
        case .cancelled,
             .timedOut,
             .networkConnectionLost,
             .notConnectedToInternet,
             .cannotConnectToHost,
             .cannotFindHost,
             .dnsLookupFailed,
             .internationalRoamingOff,
             .callIsActive,
             .dataNotAllowed:
            return true
        default:
            return false
        }
    }
}
