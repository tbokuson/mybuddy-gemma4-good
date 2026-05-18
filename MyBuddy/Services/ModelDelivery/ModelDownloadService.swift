import CryptoKit
import Foundation

protocol ModelDeliveryControlling: AnyObject {
    var manifest: ModelDeliveryManifest? { get }
    func assessAvailability() -> ModelAvailabilityReport?
    func availableDiskSpaceBytes() -> Int64?
    func downloadRequiredAssets(progress: @escaping @Sendable (ModelDownloadProgressSnapshot) -> Void) async throws -> ModelAvailabilityReport
}

final class ModelDeliveryController: ModelDeliveryControlling {
    let manifest: ModelDeliveryManifest?

    private let store: ModelAssetStore
    private let downloader: ModelDownloadService

    init(
        manifest: ModelDeliveryManifest? = ModelDeliveryManifest.loadFromBundle(),
        store: ModelAssetStore = ModelAssetStore(),
        downloader: ModelDownloadService = .shared
    ) {
        self.manifest = manifest
        self.store = store
        self.downloader = downloader
    }

    func assessAvailability() -> ModelAvailabilityReport? {
        guard let manifest else { return nil }
        try? downloader.installVerifiedStagedDownloads(for: manifest)
        return store.availabilityReport(for: manifest)
    }

    func availableDiskSpaceBytes() -> Int64? {
        store.availableDiskSpaceBytes()
    }

    func downloadRequiredAssets(progress: @escaping @Sendable (ModelDownloadProgressSnapshot) -> Void) async throws -> ModelAvailabilityReport {
        guard let manifest else {
            throw ModelDeliveryError.manifestMissing
        }

        try downloader.installVerifiedStagedDownloads(for: manifest)
        let initialReport = store.availabilityReport(for: manifest)
        let pendingAssets = (initialReport.missingAssets + initialReport.invalidAssets.map(\.asset))
            .reduce(into: [String: ModelAssetManifest]()) { result, asset in
                result[asset.id] = asset
            }
            .values
            .sorted { $0.displayName < $1.displayName }

        if pendingAssets.isEmpty {
            return initialReport
        }

        let unavailableSources = pendingAssets.filter { !$0.isChunkDownloadConfigured }
        if !unavailableSources.isEmpty {
            throw ModelDeliveryError.downloadSourceMissing(unavailableSources.map(\.displayName))
        }

        if let availableBytes = store.availableDiskSpaceBytes(),
           availableBytes < manifest.requiredFreeSpaceBytes {
            throw ModelDeliveryError.insufficientDiskSpace(
                requiredBytes: manifest.requiredFreeSpaceBytes,
                availableBytes: availableBytes
            )
        }

        let totalExpectedBytes = pendingAssets.reduce(into: Int64.zero) { partialResult, asset in
            partialResult += asset.expectedSizeBytes
        }
        var completedAssetCount = 0

        for asset in pendingAssets {
            let completedCountBeforeCurrentAsset = completedAssetCount
            let progressBaseBytes = pendingAssets.prefix(completedCountBeforeCurrentAsset).reduce(into: Int64.zero) { partialResult, prefixAsset in
                partialResult += prefixAsset.expectedSizeBytes
            }

            let result = try await downloader.download(asset: asset) { currentBytes, expectedBytes in
                progress(
                    ModelDownloadProgressSnapshot(
                        assetID: asset.id,
                        assetDisplayName: asset.displayName,
                        completedAssetCount: completedCountBeforeCurrentAsset,
                        totalAssetCount: pendingAssets.count,
                        receivedBytesForCurrentAsset: currentBytes,
                        expectedBytesForCurrentAsset: expectedBytes,
                        totalExpectedBytes: totalExpectedBytes,
                        totalReceivedBytes: progressBaseBytes + currentBytes
                    )
                )
            }

            guard result.fileSizeBytes == asset.expectedSizeBytes else {
                downloader.discardPartialDownload(asset: asset)
                throw ModelDeliveryError.validationFailed("\(asset.displayName) のサイズが一致しません。")
            }
            guard result.sha256.caseInsensitiveCompare(asset.sha256) == .orderedSame else {
                downloader.discardPartialDownload(asset: asset)
                throw ModelDeliveryError.validationFailed("\(asset.displayName) のチェックサムが一致しません。")
            }

            try store.installDownloadedAsset(
                tempURL: result.temporaryFileURL,
                asset: asset,
                manifestVersion: manifest.version,
                sha256: result.sha256,
                fileSizeBytes: result.fileSizeBytes
            )
            completedAssetCount += 1
        }

        return store.availabilityReport(for: manifest)
    }
}

struct ModelDownloadResult: Sendable {
    let temporaryFileURL: URL
    let fileSizeBytes: Int64
    let sha256: String
}

final class ModelDownloadService: NSObject {
    static let shared = ModelDownloadService()
    private static let maxConcurrentChunkDownloads = 6
    fileprivate static let chunkProgressUpdateIntervalBytes: Int64 = 1_048_576

    private let fileManager: FileManager
    private let assetStore: ModelAssetStore
    private let sessionConfigurationProvider: () -> URLSessionConfiguration

    init(
        fileManager: FileManager = .default,
        assetStore: ModelAssetStore = ModelAssetStore(),
        sessionConfigurationProvider: @escaping () -> URLSessionConfiguration = { URLSessionConfiguration.default }
    ) {
        self.fileManager = fileManager
        self.assetStore = assetStore
        self.sessionConfigurationProvider = sessionConfigurationProvider
    }

    func download(
        asset: ModelAssetManifest,
        progress: @escaping @Sendable (Int64, Int64) -> Void
    ) async throws -> ModelDownloadResult {
        guard let chunkBaseURL = asset.chunkBaseURL, !asset.chunks.isEmpty else {
            throw ModelDeliveryError.downloadSourceMissing([asset.displayName])
        }

        let configuration = sessionConfigurationProvider()
        configuration.waitsForConnectivity = true
        configuration.networkServiceType = .responsiveData
        configuration.httpMaximumConnectionsPerHost = Self.maxConcurrentChunkDownloads
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }

        let sortedChunks = asset.chunks.sorted { $0.index < $1.index }
        let progressTracker = ChunkDownloadProgressTracker()
        var pendingChunks: [ModelAssetChunkManifest] = []

        for chunk in sortedChunks {
            let chunkURL = try assetStore.chunkDownloadURL(for: asset, chunk: chunk)
            if fileSize(at: chunkURL) == chunk.expectedSizeBytes {
                let receivedBytes = await progressTracker.update(chunk: chunk, bytes: chunk.expectedSizeBytes)
                progress(receivedBytes, asset.expectedSizeBytes)
            } else {
                if fileManager.fileExists(atPath: chunkURL.path) {
                    try? fileManager.removeItem(at: chunkURL)
                }
                let partialChunkURL = try assetStore.partialChunkDownloadURL(for: asset, chunk: chunk)
                let partialBytes = min(fileSize(at: partialChunkURL), chunk.expectedSizeBytes)
                if partialBytes > 0 {
                    let receivedBytes = await progressTracker.update(chunk: chunk, bytes: partialBytes)
                    progress(receivedBytes, asset.expectedSizeBytes)
                }
                pendingChunks.append(chunk)
            }
        }

        if !pendingChunks.isEmpty {
            try await downloadChunks(
                pendingChunks,
                asset: asset,
                chunkBaseURL: chunkBaseURL,
                session: session,
                progressTracker: progressTracker,
                progress: progress
            )
        }

        let assembledURL = try assetStore.partialDownloadURL(for: asset)
        try assembleChunks(sortedChunks, for: asset, to: assembledURL)
        let sha256 = try ModelAssetHasher.sha256(forFileAt: assembledURL)
        return ModelDownloadResult(
            temporaryFileURL: assembledURL,
            fileSizeBytes: fileSize(at: assembledURL),
            sha256: sha256
        )
    }

    func discardPartialDownload(asset: ModelAssetManifest) {
        if let partialURL = try? assetStore.partialDownloadURL(for: asset),
           fileManager.fileExists(atPath: partialURL.path) {
            try? fileManager.removeItem(at: partialURL)
        }
        if let chunksURL = try? assetStore.chunkDownloadsDirectoryURL(for: asset),
           fileManager.fileExists(atPath: chunksURL.path) {
            try? fileManager.removeItem(at: chunksURL)
        }
    }

    func installVerifiedStagedDownloads(for manifest: ModelDeliveryManifest) throws {
        for asset in manifest.assets {
            let stagedURL = try assetStore.partialDownloadURL(for: asset)
            guard fileManager.fileExists(atPath: stagedURL.path) else { continue }

            let fileSize = fileSize(at: stagedURL)
            guard fileSize == asset.expectedSizeBytes else {
                try? fileManager.removeItem(at: stagedURL)
                continue
            }

            let sha256 = try ModelAssetHasher.sha256(forFileAt: stagedURL)
            guard sha256.caseInsensitiveCompare(asset.sha256) == .orderedSame else {
                try? fileManager.removeItem(at: stagedURL)
                continue
            }

            try assetStore.installDownloadedAsset(
                tempURL: stagedURL,
                asset: asset,
                manifestVersion: manifest.version,
                sha256: sha256,
                fileSizeBytes: fileSize
            )
        }
    }

    private func downloadChunks(
        _ chunks: [ModelAssetChunkManifest],
        asset: ModelAssetManifest,
        chunkBaseURL: URL,
        session: URLSession,
        progressTracker: ChunkDownloadProgressTracker,
        progress: @escaping @Sendable (Int64, Int64) -> Void
    ) async throws {
        var iterator = chunks.makeIterator()

        try await withThrowingTaskGroup(of: ModelAssetChunkManifest.self) { group in
            for _ in 0..<Self.maxConcurrentChunkDownloads {
                guard let chunk = iterator.next() else { break }
                group.addTask {
                    try await self.downloadChunk(
                        chunk,
                        asset: asset,
                        chunkBaseURL: chunkBaseURL,
                        session: session,
                        progressTracker: progressTracker,
                        progress: progress
                    )
                    return chunk
                }
            }

            while let completedChunk = try await group.next() {
                let receivedBytes = await progressTracker.update(chunk: completedChunk, bytes: completedChunk.expectedSizeBytes)
                progress(receivedBytes, asset.expectedSizeBytes)

                if let nextChunk = iterator.next() {
                    group.addTask {
                        try await self.downloadChunk(
                            nextChunk,
                            asset: asset,
                            chunkBaseURL: chunkBaseURL,
                            session: session,
                            progressTracker: progressTracker,
                            progress: progress
                        )
                        return nextChunk
                    }
                }
            }
        }
    }

    private func downloadChunk(
        _ chunk: ModelAssetChunkManifest,
        asset: ModelAssetManifest,
        chunkBaseURL: URL,
        session: URLSession,
        progressTracker: ChunkDownloadProgressTracker,
        progress: @escaping @Sendable (Int64, Int64) -> Void
    ) async throws {
        let destinationURL = try assetStore.chunkDownloadURL(for: asset, chunk: chunk)
        let partialURL = try assetStore.partialChunkDownloadURL(for: asset, chunk: chunk)
        var resumeBytes = fileSize(at: partialURL)

        if resumeBytes == chunk.expectedSizeBytes {
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
            try fileManager.moveItem(at: partialURL, to: destinationURL)
            return
        }

        if resumeBytes > chunk.expectedSizeBytes {
            try? fileManager.removeItem(at: partialURL)
            resumeBytes = 0
        }

        var request = URLRequest(url: chunk.downloadURL(relativeTo: chunkBaseURL))
        request.timeoutInterval = 90
        if resumeBytes > 0 {
            request.setValue("bytes=\(resumeBytes)-", forHTTPHeaderField: "Range")
        }

        let chunkDelegate = ChunkDataDownloadDelegate(
            chunk: chunk,
            partialURL: partialURL,
            resumeBytes: resumeBytes,
            expectedAssetBytes: asset.expectedSizeBytes,
            progressTracker: progressTracker,
            progress: progress,
            fileManager: fileManager
        )

        do {
            try await chunkDelegate.download(request: request, configuration: session.configuration)
        } catch {
            throw mapNetworkError(error)
        }

        guard fileSize(at: partialURL) == chunk.expectedSizeBytes else {
            try? fileManager.removeItem(at: destinationURL)
            throw ModelDeliveryError.validationFailed("チャンク \(chunk.fileName) のサイズが一致しません。")
        }

        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }
        try fileManager.moveItem(at: partialURL, to: destinationURL)
        let receivedBytes = await progressTracker.update(chunk: chunk, bytes: chunk.expectedSizeBytes)
        progress(receivedBytes, asset.expectedSizeBytes)
    }

    private func assembleChunks(
        _ chunks: [ModelAssetChunkManifest],
        for asset: ModelAssetManifest,
        to outputURL: URL
    ) throws {
        if fileManager.fileExists(atPath: outputURL.path) {
            try fileManager.removeItem(at: outputURL)
        }
        fileManager.createFile(atPath: outputURL.path, contents: nil)

        let outputHandle = try FileHandle(forWritingTo: outputURL)
        defer { try? outputHandle.close() }

        for chunk in chunks {
            let chunkURL = try assetStore.chunkDownloadURL(for: asset, chunk: chunk)
            guard fileSize(at: chunkURL) == chunk.expectedSizeBytes else {
                throw ModelDeliveryError.validationFailed("チャンク \(chunk.fileName) が不足しています。")
            }

            do {
                let inputHandle = try FileHandle(forReadingFrom: chunkURL)
                defer { try? inputHandle.close() }

                while true {
                    let data = try inputHandle.read(upToCount: 1_048_576) ?? Data()
                    if data.isEmpty { break }
                    try outputHandle.write(contentsOf: data)
                }
            }
        }
    }

    private func fileSize(at url: URL) -> Int64 {
        guard let value = try? fileManager.attributesOfItem(atPath: url.path)[.size] as? NSNumber else {
            return 0
        }
        return value.int64Value
    }

    private func mapNetworkError(_ error: Error) -> Error {
        if let deliveryError = error as? ModelDeliveryError {
            return deliveryError
        }
        if let urlError = error as? URLError {
            return ModelDeliveryError.network(urlError.localizedDescription)
        }
        return error
    }
}

private actor ChunkDownloadProgressTracker {
    private var completedChunkBytes: [Int: Int64] = [:]

    func update(chunk: ModelAssetChunkManifest, bytes: Int64) -> Int64 {
        completedChunkBytes[chunk.index] = min(max(0, bytes), chunk.expectedSizeBytes)
        return completedChunkBytes.values.reduce(0, +)
    }
}

private final class ChunkDataDownloadDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let chunk: ModelAssetChunkManifest
    private let partialURL: URL
    private let resumeBytes: Int64
    private let expectedAssetBytes: Int64
    private let progressTracker: ChunkDownloadProgressTracker
    private let progress: @Sendable (Int64, Int64) -> Void
    private let fileManager: FileManager

    private var lastReportedBytes: Int64
    private var currentBytes: Int64
    private var fileHandle: FileHandle?
    private var continuation: CheckedContinuation<Void, Error>?
    private var failure: Error?
    private var session: URLSession?

    init(
        chunk: ModelAssetChunkManifest,
        partialURL: URL,
        resumeBytes: Int64,
        expectedAssetBytes: Int64,
        progressTracker: ChunkDownloadProgressTracker,
        progress: @escaping @Sendable (Int64, Int64) -> Void,
        fileManager: FileManager
    ) {
        self.chunk = chunk
        self.partialURL = partialURL
        self.resumeBytes = resumeBytes
        self.expectedAssetBytes = expectedAssetBytes
        self.progressTracker = progressTracker
        self.progress = progress
        self.fileManager = fileManager
        self.lastReportedBytes = resumeBytes
        self.currentBytes = resumeBytes
    }

    func download(request: URLRequest, configuration: URLSessionConfiguration) async throws {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
            self.session = session
            session.dataTask(with: request).resume()
        }
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        guard let httpResponse = response as? HTTPURLResponse else {
            fail(ModelDeliveryError.invalidResponse("HTTPレスポンスを取得できません。"))
            completionHandler(.cancel)
            return
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            fail(ModelDeliveryError.invalidResponse("status \(httpResponse.statusCode)"))
            completionHandler(.cancel)
            return
        }

        let shouldAppend = resumeBytes > 0 && httpResponse.statusCode == 206
        let shouldRestart = resumeBytes == 0 || httpResponse.statusCode == 200

        do {
            if shouldRestart {
                if fileManager.fileExists(atPath: partialURL.path) {
                    try fileManager.removeItem(at: partialURL)
                }
                fileManager.createFile(atPath: partialURL.path, contents: nil)
                currentBytes = 0
                lastReportedBytes = 0
            } else if shouldAppend {
                currentBytes = resumeBytes
                lastReportedBytes = resumeBytes
            } else {
                throw ModelDeliveryError.invalidResponse("Range再開に対応しない応答です: status \(httpResponse.statusCode)")
            }

            fileHandle = try FileHandle(forWritingTo: partialURL)
            try fileHandle?.seekToEnd()
            completionHandler(.allow)
        } catch {
            fail(error)
            completionHandler(.cancel)
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        do {
            try fileHandle?.write(contentsOf: data)
            currentBytes = min(chunk.expectedSizeBytes, currentBytes + Int64(data.count))
            reportProgressIfNeeded(force: currentBytes == chunk.expectedSizeBytes)
        } catch {
            fail(error)
            dataTask.cancel()
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        try? fileHandle?.close()
        fileHandle = nil
        session.invalidateAndCancel()

        if let failure {
            continuation?.resume(throwing: failure)
        } else if let error {
            continuation?.resume(throwing: error)
        } else {
            reportProgressIfNeeded(force: true)
            continuation?.resume()
        }
        continuation = nil
        self.session = nil
    }

    private func reportProgressIfNeeded(force: Bool) {
        guard force || currentBytes - lastReportedBytes >= ModelDownloadService.chunkProgressUpdateIntervalBytes else {
            return
        }
        lastReportedBytes = currentBytes
        let bytes = currentBytes

        Task {
            let receivedBytes = await progressTracker.update(chunk: chunk, bytes: bytes)
            progress(receivedBytes, expectedAssetBytes)
        }
    }

    private func fail(_ error: Error) {
        if failure == nil {
            failure = error
        }
    }
}
