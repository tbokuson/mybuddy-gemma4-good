import Foundation

struct ModelDeliveryManifest: Codable, Sendable {
    let version: String
    let requiredFreeSpaceBytes: Int64
    let assets: [ModelAssetManifest]

    var totalBytes: Int64 {
        assets.reduce(into: Int64.zero) { partialResult, asset in
            partialResult += asset.expectedSizeBytes
        }
    }

    var assetNames: [String] {
        assets.map(\.displayName)
    }

    var isDownloadConfigured: Bool {
        assets.allSatisfy(\.isChunkDownloadConfigured)
    }

    static func loadFromBundle(_ bundle: Bundle = .main) -> ModelDeliveryManifest? {
        guard let url = bundle.url(forResource: "ModelDeliveryManifest", withExtension: "plist"),
              let data = try? Data(contentsOf: url) else {
            return nil
        }

        let decoder = PropertyListDecoder()
        return try? decoder.decode(ModelDeliveryManifest.self, from: data)
    }
}

struct ModelAssetManifest: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let displayName: String
    let fileName: String
    let expectedSizeBytes: Int64
    let sha256: String
    let chunkBaseURLString: String?
    let chunks: [ModelAssetChunkManifest]

    var chunkBaseURL: URL? {
        guard let chunkBaseURLString,
              !chunkBaseURLString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return URL(string: chunkBaseURLString)
    }

    var isChunkDownloadConfigured: Bool {
        guard chunkBaseURL != nil, !chunks.isEmpty else { return false }
        return chunks.allSatisfy { $0.expectedSizeBytes > 0 && !$0.fileName.isEmpty }
    }
}

struct ModelAssetChunkManifest: Codable, Hashable, Identifiable, Sendable {
    let index: Int
    let fileName: String
    let expectedSizeBytes: Int64

    var id: Int { index }

    func downloadURL(relativeTo baseURL: URL) -> URL {
        baseURL.appendingPathComponent(fileName)
    }
}

struct ModelAvailabilityReport: Sendable {
    let manifest: ModelDeliveryManifest
    let assetStates: [ModelAssetState]

    var isReady: Bool {
        assetStates.allSatisfy(\.isAvailable)
    }

    var missingAssets: [ModelAssetManifest] {
        assetStates.compactMap { state in
            guard case .missing = state.verification else { return nil }
            return state.asset
        }
    }

    var invalidAssets: [ModelAssetState] {
        assetStates.filter { !$0.isAvailable && !$0.isMissing }
    }
}

struct ModelAssetState: Sendable {
    enum Verification: Sendable, Equatable {
        case available
        case missing
        case sizeMismatch(expected: Int64, actual: Int64)
        case receiptMissing
        case receiptMismatch
    }

    let asset: ModelAssetManifest
    let location: ModelAssetLocation
    let url: URL?
    let verification: Verification

    var isAvailable: Bool {
        verification == .available
    }

    var isMissing: Bool {
        verification == .missing
    }
}

enum ModelAssetLocation: String, Sendable {
    case applicationSupport
    case bundle
    case documents
    case missing
}

struct ModelAssetReceipt: Codable, Sendable, Equatable {
    let manifestVersion: String
    let fileSizeBytes: Int64
    let sha256: String
    let verifiedAt: Date
}

struct ModelDownloadProgressSnapshot: Sendable, Equatable {
    let assetID: String
    let assetDisplayName: String
    let completedAssetCount: Int
    let totalAssetCount: Int
    let receivedBytesForCurrentAsset: Int64
    let expectedBytesForCurrentAsset: Int64
    let totalExpectedBytes: Int64
    let totalReceivedBytes: Int64

    var currentAssetFractionCompleted: Double {
        guard expectedBytesForCurrentAsset > 0 else { return 0 }
        return min(1, Double(receivedBytesForCurrentAsset) / Double(expectedBytesForCurrentAsset))
    }

    var overallFractionCompleted: Double {
        guard totalExpectedBytes > 0 else { return 0 }
        return min(1, Double(totalReceivedBytes) / Double(totalExpectedBytes))
    }
}

struct ModelSetupRequirement: Sendable, Equatable {
    let assetNames: [String]
    let totalBytes: Int64
    let requiredFreeSpaceBytes: Int64
    let downloadConfigured: Bool
    let missingAssetNames: [String]
    let invalidAssetNames: [String]

    var hasRecoverableAssets: Bool {
        !missingAssetNames.isEmpty || !invalidAssetNames.isEmpty
    }

    var missingOrInvalidAssetNames: [String] {
        Array(Set(missingAssetNames + invalidAssetNames)).sorted()
    }
}

enum ModelDeliveryError: LocalizedError, Equatable, Sendable {
    case manifestMissing
    case downloadSourceMissing([String])
    case insufficientDiskSpace(requiredBytes: Int64, availableBytes: Int64)
    case invalidResponse(String)
    case network(String)
    case fileSystem(String)
    case validationFailed(String)

    var errorDescription: String? {
        let isEnglish = AppLanguageMode.currentResolved == .english
        switch self {
        case .manifestMissing:
            return isEnglish ? "Download configuration was not found." : "ダウンロード設定ファイルが見つかりません。"
        case .downloadSourceMissing(let assets):
            return isEnglish
                ? "Download source is not configured: \(assets.joined(separator: ", "))"
                : "ダウンロード先が設定されていません: \(assets.joined(separator: "、"))"
        case .insufficientDiskSpace(let requiredBytes, let availableBytes):
            let required = ByteCountFormatter.string(fromByteCount: requiredBytes, countStyle: .file)
            let available = ByteCountFormatter.string(fromByteCount: availableBytes, countStyle: .file)
            return isEnglish
                ? "Not enough free space. Required: \(required) / Available: \(available)"
                : "空き容量が不足しています。必要: \(required) / 利用可能: \(available)"
        case .invalidResponse(let message):
            return isEnglish ? "The download server returned an invalid response: \(message)" : "ダウンロードサーバーの応答が不正です: \(message)"
        case .network(let message):
            return isEnglish ? "Download failed: \(message)" : "ダウンロードに失敗しました: \(message)"
        case .fileSystem(let message):
            return isEnglish ? "Failed to save the file: \(message)" : "ファイルの保存に失敗しました: \(message)"
        case .validationFailed(let message):
            return isEnglish ? "Failed to verify the downloaded files: \(message)" : "ダウンロード内容の確認に失敗しました: \(message)"
        }
    }
}

extension ModelDeliveryManifest {
    var setupRequirement: ModelSetupRequirement {
        ModelSetupRequirement(
            assetNames: assetNames,
            totalBytes: totalBytes,
            requiredFreeSpaceBytes: requiredFreeSpaceBytes,
            downloadConfigured: isDownloadConfigured,
            missingAssetNames: assetNames,
            invalidAssetNames: []
        )
    }
}

extension ModelAvailabilityReport {
    var setupRequirement: ModelSetupRequirement {
        ModelSetupRequirement(
            assetNames: manifest.assetNames,
            totalBytes: manifest.totalBytes,
            requiredFreeSpaceBytes: manifest.requiredFreeSpaceBytes,
            downloadConfigured: manifest.isDownloadConfigured,
            missingAssetNames: missingAssets.map(\.displayName),
            invalidAssetNames: invalidAssets.map(\.asset.displayName)
        )
    }
}
