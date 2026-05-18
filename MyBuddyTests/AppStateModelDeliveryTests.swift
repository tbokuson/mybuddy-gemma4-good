import XCTest
@testable import MyBuddy

@MainActor
final class AppStateModelDeliveryTests: XCTestCase {
    override func setUp() {
        super.setUp()
        UserDefaults.standard.set(AppLanguageMode.japanese.rawValue, forKey: AppLanguageMode.storageKey)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: AppLanguageMode.storageKey)
        super.tearDown()
    }

    private final class MockLLMService: LLMServiceProtocol {
        var isLoaded = false
        var isGenerating = false
        var visionLoaded = false
        var backendDescription = "mock"
        var requiresLocalModelAssets = true
        var loadModelCallCount = 0
        var loadModelError: Error?
        var releaseBackgroundResourcesCallCount = 0
        var handleMemoryPressureCallCount = 0

        func loadModel() async throws {
            loadModelCallCount += 1
            if let loadModelError {
                throw loadModelError
            }
            isLoaded = true
        }

        func generate(prompt: String, maxTokens: Int, samplingProfile: LLMSamplingProfile) async throws -> String {
            ""
        }

        func generateStream(prompt: String, maxTokens: Int, samplingProfile: LLMSamplingProfile) -> AsyncThrowingStream<String, Error> {
            AsyncThrowingStream { continuation in
                continuation.finish()
            }
        }

        func loadVision() async throws {}
        func unloadVision() {}
        func releaseBackgroundResources() {
            releaseBackgroundResourcesCallCount += 1
        }
        func handleMemoryPressure() {
            handleMemoryPressureCallCount += 1
        }

        func generateWithImage(
            prompt: String,
            imageData: Data,
            maxTokens: Int,
            samplingProfile: LLMSamplingProfile
        ) async throws -> String {
            ""
        }
    }

    private final class MockModelDeliveryController: ModelDeliveryControlling {
        let manifest: ModelDeliveryManifest?
        var availableDiskSpace: Int64?
        var assessReport: ModelAvailabilityReport?
        var downloadResults: [Result<ModelAvailabilityReport, Error>] = []
        var assessAvailabilityCallCount = 0
        var downloadCallCount = 0
        var progressSnapshots: [ModelDownloadProgressSnapshot] = []

        init(manifest: ModelDeliveryManifest?, assessReport: ModelAvailabilityReport? = nil, availableDiskSpace: Int64? = nil) {
            self.manifest = manifest
            self.assessReport = assessReport
            self.availableDiskSpace = availableDiskSpace
        }

        func assessAvailability() -> ModelAvailabilityReport? {
            assessAvailabilityCallCount += 1
            return assessReport
        }

        func availableDiskSpaceBytes() -> Int64? {
            availableDiskSpace
        }

        func downloadRequiredAssets(progress: @escaping @Sendable (ModelDownloadProgressSnapshot) -> Void) async throws -> ModelAvailabilityReport {
            downloadCallCount += 1
            for snapshot in progressSnapshots {
                progress(snapshot)
            }

            guard !downloadResults.isEmpty else {
                throw ModelDeliveryError.network("テスト結果が未設定です。")
            }
            return try downloadResults.removeFirst().get()
        }
    }

    func testPrepareForLaunchShowsSetupWhenModelsAreMissing() async {
        let manifest = makeManifest()
        let report = makeReport(manifest: manifest, missingIDs: ["text-model", "vision-model"])
        let llmService = MockLLMService()
        let controller = MockModelDeliveryController(manifest: manifest, assessReport: report)
        let appState = AppState(
            llmService: llmService,
            modelDeliveryController: controller,
            shouldAutoInitializeLLM: true
        )

        await appState.prepareForLaunch()

        XCTAssertEqual(appState.modelSetupState, .setupRequired(report.setupRequirement))
        XCTAssertEqual(appState.llmStatus, .notLoaded)
        XCTAssertEqual(llmService.loadModelCallCount, 0)
    }

    func testPrepareForLaunchLoadsLLMWhenModelsAreReady() async {
        let manifest = makeManifest()
        let readyReport = makeReport(manifest: manifest)
        let llmService = MockLLMService()
        let controller = MockModelDeliveryController(manifest: manifest, assessReport: readyReport)
        let appState = AppState(
            llmService: llmService,
            modelDeliveryController: controller,
            shouldAutoInitializeLLM: true
        )

        await appState.prepareForLaunch()

        XCTAssertEqual(appState.modelSetupState, .ready)
        XCTAssertEqual(appState.llmStatus, .loaded)
        XCTAssertEqual(llmService.loadModelCallCount, 1)
    }

    func testUserDataResetKeepsReadyModelSetupState() async {
        let manifest = makeManifest()
        let readyReport = makeReport(manifest: manifest)
        let missingReport = makeReport(manifest: manifest, missingIDs: ["text-model", "vision-model"])
        let llmService = MockLLMService()
        let controller = MockModelDeliveryController(manifest: manifest, assessReport: readyReport)
        let appState = AppState(
            llmService: llmService,
            modelDeliveryController: controller,
            shouldAutoInitializeLLM: true
        )

        await appState.prepareForLaunch()
        controller.assessReport = missingReport
        let assessCallCountAfterLaunch = controller.assessAvailabilityCallCount

        appState.preserveModelSetupAfterUserDataReset()

        XCTAssertEqual(appState.modelSetupState, .ready)
        XCTAssertEqual(appState.llmStatus, .loaded)
        XCTAssertEqual(controller.downloadCallCount, 0)
        XCTAssertEqual(controller.assessAvailabilityCallCount, assessCallCountAfterLaunch)
    }

    func testStartModelSetupTransitionsToReadyAfterDownload() async {
        let manifest = makeManifest()
        let missingReport = makeReport(manifest: manifest, missingIDs: ["text-model", "vision-model"])
        let readyReport = makeReport(manifest: manifest)
        let llmService = MockLLMService()
        let controller = MockModelDeliveryController(manifest: manifest, assessReport: missingReport, availableDiskSpace: 9_000_000_000)
        controller.progressSnapshots = [
            ModelDownloadProgressSnapshot(
                assetID: "text-model",
                assetDisplayName: "会話モデル",
                completedAssetCount: 0,
                totalAssetCount: 2,
                receivedBytesForCurrentAsset: 512,
                expectedBytesForCurrentAsset: 1_024,
                totalExpectedBytes: 2_048,
                totalReceivedBytes: 512
            )
        ]
        controller.downloadResults = [.success(readyReport)]
        let appState = AppState(
            llmService: llmService,
            modelDeliveryController: controller,
            shouldAutoInitializeLLM: true
        )

        await appState.startModelSetup()

        XCTAssertEqual(appState.modelSetupState, .ready)
        XCTAssertEqual(appState.llmStatus, .loaded)
        XCTAssertEqual(controller.downloadCallCount, 1)
        XCTAssertEqual(llmService.loadModelCallCount, 1)
    }

    func testRetryModelSetupRecoversAfterValidationFailure() async {
        let manifest = makeManifest()
        let missingReport = makeReport(manifest: manifest, missingIDs: ["text-model", "vision-model"])
        let readyReport = makeReport(manifest: manifest)
        let llmService = MockLLMService()
        let controller = MockModelDeliveryController(manifest: manifest, assessReport: missingReport, availableDiskSpace: 9_000_000_000)
        controller.downloadResults = [
            .failure(ModelDeliveryError.validationFailed("サイズが一致しません。")),
            .success(readyReport)
        ]
        let appState = AppState(
            llmService: llmService,
            modelDeliveryController: controller,
            shouldAutoInitializeLLM: true
        )

        await appState.startModelSetup()
        XCTAssertEqual(
            appState.modelSetupState,
            .failed(missingReport.setupRequirement, "ダウンロード内容の確認に失敗しました: サイズが一致しません。")
        )
        XCTAssertEqual(appState.llmStatus, .notLoaded)

        await appState.retryModelSetup()

        XCTAssertEqual(appState.modelSetupState, .ready)
        XCTAssertEqual(appState.llmStatus, .loaded)
        XCTAssertEqual(controller.downloadCallCount, 2)
    }

    func testNetworkInterruptionKeepsDownloadingStateAndAutoResumesWhenActive() async throws {
        let manifest = makeManifest()
        let missingReport = makeReport(manifest: manifest, missingIDs: ["text-model", "vision-model"])
        let readyReport = makeReport(manifest: manifest)
        let llmService = MockLLMService()
        let controller = MockModelDeliveryController(manifest: manifest, assessReport: missingReport, availableDiskSpace: 9_000_000_000)
        controller.progressSnapshots = [
            ModelDownloadProgressSnapshot(
                assetID: "text-model",
                assetDisplayName: "会話モデル",
                completedAssetCount: 0,
                totalAssetCount: 2,
                receivedBytesForCurrentAsset: 512,
                expectedBytesForCurrentAsset: 1_024,
                totalExpectedBytes: 2_048,
                totalReceivedBytes: 512
            )
        ]
        controller.downloadResults = [
            .failure(ModelDeliveryError.network("通信が中断されました。")),
            .success(readyReport)
        ]
        let appState = AppState(
            llmService: llmService,
            modelDeliveryController: controller,
            shouldAutoInitializeLLM: true
        )

        await appState.startModelSetup()

        XCTAssertEqual(appState.modelSetupState, .ready)
        XCTAssertEqual(appState.llmStatus, .loaded)
        XCTAssertEqual(controller.downloadCallCount, 2)
    }

    func testPrepareForLaunchSkipsSetupForBackendThatDoesNotNeedLocalAssets() async {
        let llmService = MockLLMService()
        llmService.requiresLocalModelAssets = false
        let controller = MockModelDeliveryController(manifest: nil, assessReport: nil)
        let appState = AppState(
            llmService: llmService,
            modelDeliveryController: controller,
            shouldAutoInitializeLLM: true
        )

        await appState.prepareForLaunch()

        XCTAssertEqual(appState.modelSetupState, .ready)
        XCTAssertEqual(appState.llmStatus, .loaded)
        XCTAssertEqual(llmService.loadModelCallCount, 1)
        XCTAssertEqual(controller.downloadCallCount, 0)
    }

    func testHandleScenePhaseChangeReleasesBackgroundResources() async {
        let llmService = MockLLMService()
        let controller = MockModelDeliveryController(manifest: nil, assessReport: nil)
        let appState = AppState(
            llmService: llmService,
            modelDeliveryController: controller,
            shouldAutoInitializeLLM: false
        )

        appState.handleScenePhaseChange(.active)
        XCTAssertEqual(llmService.releaseBackgroundResourcesCallCount, 0)

        appState.handleScenePhaseChange(.background)
        XCTAssertEqual(llmService.releaseBackgroundResourcesCallCount, 1)
    }

    private func makeManifest(downloadConfigured: Bool = true) -> ModelDeliveryManifest {
        ModelDeliveryManifest(
            version: "1",
            requiredFreeSpaceBytes: 2_000,
            assets: [
                ModelAssetManifest(
                    id: "text-model",
                    displayName: "会話モデル",
                    fileName: "gemma.gguf",
                    expectedSizeBytes: 1_000,
                    sha256: "abc",
                    chunkBaseURLString: downloadConfigured ? "https://example.com/chunks/gemma" : nil,
                    chunks: downloadConfigured ? [makeChunk(fileName: "gemma.gguf.part.000", size: 1_000)] : []
                ),
                ModelAssetManifest(
                    id: "vision-model",
                    displayName: "画像理解モデル",
                    fileName: "mmproj.gguf",
                    expectedSizeBytes: 1_000,
                    sha256: "def",
                    chunkBaseURLString: downloadConfigured ? "https://example.com/chunks/mmproj" : nil,
                    chunks: downloadConfigured ? [makeChunk(fileName: "mmproj.gguf.part.000", size: 1_000)] : []
                )
            ]
        )
    }

    private func makeChunk(fileName: String, size: Int64) -> ModelAssetChunkManifest {
        ModelAssetChunkManifest(index: 0, fileName: fileName, expectedSizeBytes: size)
    }

    private func makeReport(
        manifest: ModelDeliveryManifest,
        missingIDs: Set<String> = [],
        invalidIDs: Set<String> = []
    ) -> ModelAvailabilityReport {
        let states = manifest.assets.map { asset in
            if missingIDs.contains(asset.id) {
                return ModelAssetState(asset: asset, location: .missing, url: nil, verification: .missing)
            }
            if invalidIDs.contains(asset.id) {
                return ModelAssetState(
                    asset: asset,
                    location: .applicationSupport,
                    url: URL(fileURLWithPath: "/tmp/\(asset.fileName)"),
                    verification: .sizeMismatch(expected: asset.expectedSizeBytes, actual: asset.expectedSizeBytes - 1)
                )
            }
            return ModelAssetState(
                asset: asset,
                location: .applicationSupport,
                url: URL(fileURLWithPath: "/tmp/\(asset.fileName)"),
                verification: .available
            )
        }

        return ModelAvailabilityReport(manifest: manifest, assetStates: states)
    }
}
