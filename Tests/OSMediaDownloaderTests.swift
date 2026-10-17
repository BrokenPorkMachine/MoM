import Foundation

private final class MediaURLProtocol: URLProtocol {
    struct Fixture {
        let body: Data
        let declaredLength: Int
        let pauseAfterFirstChunk: TimeInterval
    }

    static let fixtures: [String: Fixture] = [
        "/replacement": .init(body: Data(repeating: 0x41, count: 131_072), declaredLength: 131_072, pauseAfterFirstChunk: 0),
        "/truncated": .init(body: Data(repeating: 0x42, count: 32), declaredLength: 64, pauseAfterFirstChunk: 0),
        "/slow": .init(body: Data(repeating: 0x43, count: 131_072), declaredLength: 131_072, pauseAfterFirstChunk: 2),
        "/retry": .init(body: Data(repeating: 0x44, count: 131_072), declaredLength: 131_072, pauseAfterFirstChunk: 1),
    ]

    private let lock = NSLock()
    private var stopped = false

    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "updates.apple.com" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url, let fixture = Self.fixtures[url.path],
              let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil,
                                             headerFields: ["Content-Length": String(fixture.declaredLength)]) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if fixture.pauseAfterFirstChunk > 0 {
            client?.urlProtocol(self, didLoad: fixture.body.prefix(65_536))
            DispatchQueue.global().asyncAfter(deadline: .now() + fixture.pauseAfterFirstChunk) { [self] in
                lock.lock(); let shouldFinish = !stopped; lock.unlock()
                guard shouldFinish else { return }
                client?.urlProtocol(self, didLoad: fixture.body.dropFirst(65_536))
                client?.urlProtocolDidFinishLoading(self)
            }
        } else {
            client?.urlProtocol(self, didLoad: fixture.body)
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {
        lock.lock(); stopped = true; lock.unlock()
    }
}

@main
enum OSMediaDownloaderTests {
    @MainActor
    private static func download(_ downloader: OSMediaDownloader, to destination: URL,
                                 progress: @escaping (Double) -> Void = { _ in }) async -> Result<URL, Error> {
        await withCheckedContinuation { continuation in
            downloader.downloadLatestMacOSRestoreImage(to: destination, progress: progress) {
                continuation.resume(returning: $0)
            }
        }
    }

    @MainActor
    private static func assertNoStagingFiles(in folder: URL) throws {
        let names = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        precondition(!names.contains { $0.hasSuffix(".download") }, "staged file was left behind")
    }

    @MainActor
    static func main() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("OSMediaDownloaderTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MediaURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        func url(_ path: String) -> URL { URL(string: "https://updates.apple.com\(path)")! }

        let destination = folder.appendingPathComponent("macOS.ipsw")
        try Data("existing image".utf8).write(to: destination)
        let replacement = OSMediaDownloader(session: session, sourceURLProvider: { url("/replacement") })
        guard case .success = await download(replacement, to: destination) else {
            fatalError("complete download did not replace existing image")
        }
        let replacementBytes = try Data(contentsOf: destination)
        precondition(replacementBytes == MediaURLProtocol.fixtures["/replacement"]!.body)
        try assertNoStagingFiles(in: folder)

        let truncated = OSMediaDownloader(session: session, sourceURLProvider: { url("/truncated") })
        guard case .failure = await download(truncated, to: destination) else {
            fatalError("truncated download was accepted")
        }
        let preservedBytes = try Data(contentsOf: destination)
        precondition(preservedBytes == MediaURLProtocol.fixtures["/replacement"]!.body)
        try assertNoStagingFiles(in: folder)

        var source = url("/slow")
        let restarted = OSMediaDownloader(session: session, sourceURLProvider: { source })
        let cancelled = Task { await download(restarted, to: destination) }
        var staged = false
        for _ in 0..<500 where !staged {
            staged = try FileManager.default.contentsOfDirectory(atPath: folder.path).contains { $0.hasSuffix(".download") }
            if !staged { try await Task.sleep(for: .milliseconds(10)) }
        }
        precondition(staged, "slow download never created a staged file")
        restarted.cancel()
        source = url("/retry")
        let retry = Task { await download(restarted, to: destination) }
        guard case .failure = await cancelled.value else { fatalError("cancelled download succeeded") }
        precondition(restarted.isDownloading, "old task cleared the active retry")
        guard case .success = await retry.value else { fatalError("retry failed") }
        let retryBytes = try Data(contentsOf: destination)
        precondition(retryBytes == MediaURLProtocol.fixtures["/retry"]!.body)
        try assertNoStagingFiles(in: folder)
        precondition(!restarted.isDownloading, "completed retry remained active")

        let rejected = OSMediaDownloader(session: session, sourceURLProvider: { URL(string: "https://example.com/foreign")! })
        guard case .failure = await download(rejected, to: destination) else {
            fatalError("non-Apple source was accepted")
        }
        print("PASS: restore-image replacement, truncation, cancellation, retry, cleanup, and source checks")
    }
}
