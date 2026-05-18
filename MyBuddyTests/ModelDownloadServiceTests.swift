import CryptoKit
import XCTest
@testable import MyBuddy

@MainActor
final class ModelDownloadServiceTests: XCTestCase {
    override func tearDown() {
        MockDownloadURLProtocol.requestHandler = nil
        super.tearDown()
    }

    func testDownloadCombinesChunks() async throws {
        let payload = Data("abcdef".utf8)
        let chunkPayloads = [
            "model.bin.part.000": Data("abc".utf8),
            "model.bin.part.001": Data("def".utf8)
        ]
        let asset = makeAsset(fileName: "model-\(UUID().uuidString).bin", payload: payload, chunkPayloads: chunkPayloads)
        let store = ModelAssetStore()
        defer { cleanup(asset: asset, store: store) }

        MockDownloadURLProtocol.requestHandler = { request in
            let body = chunkPayloads[request.url!.lastPathComponent]!
            return (
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Length": "\(body.count)"]
                )!,
                body
            )
        }

        let service = makeService(store: store)
        let result = try await service.download(asset: asset) { _, _ in }
        let resultSize = result.fileSizeBytes
        let resultHash = result.sha256
        let resultData = try Data(contentsOf: result.temporaryFileURL)

        XCTAssertEqual(resultSize, Int64(payload.count))
        XCTAssertEqual(resultHash, sha256(payload))
        XCTAssertEqual(resultData, payload)
    }

    func testDownloadReusesCompletedChunks() async throws {
        let payload = Data("abcdef".utf8)
        let chunkPayloads = [
            "model.bin.part.000": Data("abc".utf8),
            "model.bin.part.001": Data("def".utf8)
        ]
        let asset = makeAsset(fileName: "model-\(UUID().uuidString).bin", payload: payload, chunkPayloads: chunkPayloads)
        let store = ModelAssetStore()
        defer { cleanup(asset: asset, store: store) }

        let firstChunkURL = try store.chunkDownloadURL(for: asset, chunk: asset.chunks[0])
        try chunkPayloads["model.bin.part.000"]!.write(to: firstChunkURL)
        var requestedPaths: [String] = []

        MockDownloadURLProtocol.requestHandler = { request in
            requestedPaths.append(request.url!.lastPathComponent)
            let body = chunkPayloads[request.url!.lastPathComponent]!
            return (
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Length": "\(body.count)"]
                )!,
                body
            )
        }

        let service = makeService(store: store)
        let result = try await service.download(asset: asset) { _, _ in }
        let resultSize = result.fileSizeBytes
        let resultHash = result.sha256
        let resultData = try Data(contentsOf: result.temporaryFileURL)

        XCTAssertEqual(resultSize, Int64(payload.count))
        XCTAssertEqual(resultHash, sha256(payload))
        XCTAssertEqual(resultData, payload)
        XCTAssertEqual(requestedPaths, ["model.bin.part.001"])
    }

    func testDownloadResumesPartialChunkWithRangeRequest() async throws {
        let payload = Data("abcdef".utf8)
        let chunkPayloads = [
            "model.bin.part.000": payload
        ]
        let asset = makeAsset(fileName: "model-\(UUID().uuidString).bin", payload: payload, chunkPayloads: chunkPayloads)
        let store = ModelAssetStore()
        defer { cleanup(asset: asset, store: store) }

        let partialURL = try store.partialChunkDownloadURL(for: asset, chunk: asset.chunks[0])
        try Data("ab".utf8).write(to: partialURL)
        var rangeHeader: String?

        MockDownloadURLProtocol.requestHandler = { request in
            rangeHeader = request.value(forHTTPHeaderField: "Range")
            let body = Data("cdef".utf8)
            return (
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 206,
                    httpVersion: nil,
                    headerFields: ["Content-Length": "\(body.count)"]
                )!,
                body
            )
        }

        let service = makeService(store: store)
        let result = try await service.download(asset: asset) { _, _ in }
        let resultData = try Data(contentsOf: result.temporaryFileURL)

        XCTAssertEqual(rangeHeader, "bytes=2-")
        XCTAssertEqual(resultData, payload)
    }

    func testDownloadKeepsPartialChunkAfterNetworkFailure() async throws {
        let payload = Data("abcdef".utf8)
        let chunkPayloads = [
            "model.bin.part.000": payload
        ]
        let asset = makeAsset(fileName: "model-\(UUID().uuidString).bin", payload: payload, chunkPayloads: chunkPayloads)
        let store = ModelAssetStore()
        defer { cleanup(asset: asset, store: store) }

        let partialURL = try store.partialChunkDownloadURL(for: asset, chunk: asset.chunks[0])
        let partialData = Data("ab".utf8)
        try partialData.write(to: partialURL)

        MockDownloadURLProtocol.requestHandler = { _ in
            throw URLError(.networkConnectionLost)
        }

        let service = makeService(store: store)
        do {
            _ = try await service.download(asset: asset) { _, _ in }
            XCTFail("通信断では失敗する必要がある")
        } catch {
            XCTAssertEqual(try Data(contentsOf: partialURL), partialData)
        }
    }

    private func makeService(store: ModelAssetStore) -> ModelDownloadService {
        ModelDownloadService(assetStore: store) {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [MockDownloadURLProtocol.self]
            return configuration
        }
    }

    private func makeAsset(fileName: String, payload: Data, chunkPayloads: [String: Data]) -> ModelAssetManifest {
        let chunks = chunkPayloads.keys.sorted().enumerated().map { index, fileName in
            ModelAssetChunkManifest(
                index: index,
                fileName: fileName,
                expectedSizeBytes: Int64(chunkPayloads[fileName]!.count)
            )
        }
        return ModelAssetManifest(
            id: fileName,
            displayName: fileName,
            fileName: fileName,
            expectedSizeBytes: Int64(payload.count),
            sha256: sha256(payload),
            chunkBaseURLString: "https://example.com/chunks",
            chunks: chunks
        )
    }

    private func cleanup(asset: ModelAssetManifest, store: ModelAssetStore) {
        try? FileManager.default.removeItem(at: store.partialDownloadURL(for: asset))
        try? FileManager.default.removeItem(at: store.chunkDownloadsDirectoryURL(for: asset))
    }

    private func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

private final class MockDownloadURLProtocol: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let requestHandler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (response, data) = try requestHandler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
