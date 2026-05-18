import CryptoKit
import Foundation

final class ModelAssetStore {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func availabilityReport(for manifest: ModelDeliveryManifest) -> ModelAvailabilityReport {
        let states = manifest.assets.map { asset in
            state(for: asset, manifestVersion: manifest.version)
        }
        return ModelAvailabilityReport(manifest: manifest, assetStates: states)
    }

    func modelsDirectoryURL() throws -> URL {
        let appSupport = try applicationSupportDirectoryURL()
        let modelsDirectory = appSupport.appendingPathComponent("Models", isDirectory: true)
        try ensureDirectoryExists(at: modelsDirectory)
        return modelsDirectory
    }

    func destinationURL(for asset: ModelAssetManifest) throws -> URL {
        try modelsDirectoryURL().appendingPathComponent(asset.fileName)
    }

    func receiptURL(for asset: ModelAssetManifest) throws -> URL {
        try modelsDirectoryURL().appendingPathComponent("\(asset.fileName).receipt.plist")
    }

    func temporaryURL(for asset: ModelAssetManifest) throws -> URL {
        let folder = try fileManager.url(
            for: .itemReplacementDirectory,
            in: .userDomainMask,
            appropriateFor: try modelsDirectoryURL(),
            create: true
        )
        return folder.appendingPathComponent("\(asset.fileName).download")
    }

    func partialDownloadURL(for asset: ModelAssetManifest) throws -> URL {
        let folder = try modelsDirectoryURL().appendingPathComponent(".Downloads", isDirectory: true)
        try ensureDirectoryExists(at: folder)
        return folder.appendingPathComponent("\(asset.fileName).partial")
    }

    func chunkDownloadsDirectoryURL(for asset: ModelAssetManifest) throws -> URL {
        let folder = try modelsDirectoryURL()
            .appendingPathComponent(".Downloads", isDirectory: true)
            .appendingPathComponent(asset.id, isDirectory: true)
        try ensureDirectoryExists(at: folder)
        return folder
    }

    func chunkDownloadURL(for asset: ModelAssetManifest, chunk: ModelAssetChunkManifest) throws -> URL {
        try chunkDownloadsDirectoryURL(for: asset).appendingPathComponent(chunk.fileName)
    }

    func partialChunkDownloadURL(for asset: ModelAssetManifest, chunk: ModelAssetChunkManifest) throws -> URL {
        try chunkDownloadURL(for: asset, chunk: chunk).appendingPathExtension("partial")
    }

    func installDownloadedAsset(
        tempURL: URL,
        asset: ModelAssetManifest,
        manifestVersion: String,
        sha256: String,
        fileSizeBytes: Int64
    ) throws {
        let destination = try destinationURL(for: asset)
        let receipt = ModelAssetReceipt(
            manifestVersion: manifestVersion,
            fileSizeBytes: fileSizeBytes,
            sha256: sha256,
            verifiedAt: Date()
        )
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml

        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.moveItem(at: tempURL, to: destination)
        try writeReceipt(receipt, to: receiptURL(for: asset), encoder: encoder)
        if let partialURL = try? partialDownloadURL(for: asset),
           fileManager.fileExists(atPath: partialURL.path) {
            try? fileManager.removeItem(at: partialURL)
        }
        if let chunksURL = try? chunkDownloadsDirectoryURL(for: asset),
           fileManager.fileExists(atPath: chunksURL.path) {
            try? fileManager.removeItem(at: chunksURL)
        }
    }

    func availableDiskSpaceBytes() -> Int64? {
        guard let appSupport = try? applicationSupportDirectoryURL(),
              let values = try? appSupport.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]) else {
            return nil
        }
        return values.volumeAvailableCapacityForImportantUsage
    }

    func preferredURL(forFileNamed fileName: String) -> URL? {
        if let storedURL = storedURL(forFileNamed: fileName), fileManager.fileExists(atPath: storedURL.path) {
            return storedURL
        }

        let resourceName = (fileName as NSString).deletingPathExtension
        let `extension` = (fileName as NSString).pathExtension
        if let bundleURL = Bundle.main.url(forResource: resourceName, withExtension: `extension`.isEmpty ? nil : `extension`) {
            return bundleURL
        }

        guard let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return nil
        }
        let directURL = documents.appendingPathComponent(fileName)
        if fileManager.fileExists(atPath: directURL.path) {
            return directURL
        }
        if let contents = try? fileManager.contentsOfDirectory(atPath: documents.path),
           let match = contents.first(where: { $0 == fileName }) {
            return documents.appendingPathComponent(match)
        }
        return nil
    }

    private func state(for asset: ModelAssetManifest, manifestVersion: String) -> ModelAssetState {
        if let url = storedURL(forFileNamed: asset.fileName),
           fileManager.fileExists(atPath: url.path) {
            let verification = verifyStoredAsset(at: url, asset: asset, manifestVersion: manifestVersion)
            if verification == .available {
                return ModelAssetState(asset: asset, location: .applicationSupport, url: url, verification: verification)
            }
        }

        let resourceName = (asset.fileName as NSString).deletingPathExtension
        let `extension` = (asset.fileName as NSString).pathExtension
        if let bundleURL = Bundle.main.url(forResource: resourceName, withExtension: `extension`.isEmpty ? nil : `extension`),
           fileManager.fileExists(atPath: bundleURL.path) {
            let verification = verifyBundleOrLegacyAsset(at: bundleURL, asset: asset)
            if verification == .available {
                return ModelAssetState(asset: asset, location: .bundle, url: bundleURL, verification: verification)
            }
        }

        if let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first {
            let docsURL = documents.appendingPathComponent(asset.fileName)
            if fileManager.fileExists(atPath: docsURL.path) {
                let verification = verifyBundleOrLegacyAsset(at: docsURL, asset: asset)
                if verification == .available {
                    return ModelAssetState(asset: asset, location: .documents, url: docsURL, verification: verification)
                }
            }
        }

        if let storedURL = storedURL(forFileNamed: asset.fileName),
           fileManager.fileExists(atPath: storedURL.path) {
            return ModelAssetState(
                asset: asset,
                location: .applicationSupport,
                url: storedURL,
                verification: verifyStoredAsset(at: storedURL, asset: asset, manifestVersion: manifestVersion)
            )
        }

        return ModelAssetState(asset: asset, location: .missing, url: nil, verification: .missing)
    }

    private func verifyStoredAsset(at url: URL, asset: ModelAssetManifest, manifestVersion: String) -> ModelAssetState.Verification {
        guard let fileSize = fileSize(at: url) else {
            return .missing
        }
        guard fileSize == asset.expectedSizeBytes else {
            return .sizeMismatch(expected: asset.expectedSizeBytes, actual: fileSize)
        }

        guard let receiptURL = try? receiptURL(for: asset),
              let receiptData = try? Data(contentsOf: receiptURL),
              let receipt = try? PropertyListDecoder().decode(ModelAssetReceipt.self, from: receiptData) else {
            return .receiptMissing
        }

        guard receipt.manifestVersion == manifestVersion,
              receipt.fileSizeBytes == asset.expectedSizeBytes,
              receipt.sha256.caseInsensitiveCompare(asset.sha256) == .orderedSame else {
            return .receiptMismatch
        }

        return .available
    }

    private func verifyBundleOrLegacyAsset(at url: URL, asset: ModelAssetManifest) -> ModelAssetState.Verification {
        guard let fileSize = fileSize(at: url) else {
            return .missing
        }
        guard fileSize == asset.expectedSizeBytes else {
            return .sizeMismatch(expected: asset.expectedSizeBytes, actual: fileSize)
        }
        return .available
    }

    private func applicationSupportDirectoryURL() throws -> URL {
        guard let url = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw ModelDeliveryError.fileSystem("Application Support が取得できません。")
        }
        return url
    }

    private func ensureDirectoryExists(at url: URL) throws {
        if !fileManager.fileExists(atPath: url.path) {
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        }

        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        var mutableURL = url
        try mutableURL.setResourceValues(resourceValues)
        try fileManager.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: url.path)
    }

    private func writeReceipt(_ receipt: ModelAssetReceipt, to url: URL, encoder: PropertyListEncoder) throws {
        let data = try encoder.encode(receipt)
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
        try data.write(to: url, options: .atomic)
    }

    private func fileSize(at url: URL) -> Int64? {
        guard let attributes = try? fileManager.attributesOfItem(atPath: url.path),
              let value = attributes[.size] as? NSNumber else {
            return nil
        }
        return value.int64Value
    }

    private func storedURL(forFileNamed fileName: String) -> URL? {
        guard let directory = try? modelsDirectoryURL() else { return nil }
        return directory.appendingPathComponent(fileName)
    }
}

enum ModelAssetHasher {
    static func sha256(forFileAt url: URL) throws -> String {
        guard let stream = InputStream(url: url) else {
            throw ModelDeliveryError.fileSystem("ハッシュ計算用にファイルを開けません。")
        }

        stream.open()
        defer { stream.close() }

        var hasher = SHA256()
        let bufferSize = 1_048_576
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }

        while stream.hasBytesAvailable {
            let read = stream.read(buffer, maxLength: bufferSize)
            if read < 0 {
                throw ModelDeliveryError.fileSystem(stream.streamError?.localizedDescription ?? "ファイルの読み込みに失敗しました。")
            }
            if read == 0 {
                break
            }
            hasher.update(data: Data(bytes: buffer, count: read))
        }

        let digest = hasher.finalize()
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
