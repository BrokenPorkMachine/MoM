import Foundation
import Virtualization

enum OSMediaDownloadError: LocalizedError {
    case unsupportedSource
    case invalidDestination
    case missingRemoteURL
    case appleCatalogueUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedSource: "The restore image was not provided by an approved official source."
        case .invalidDestination: "Choose a local file destination for the restore image."
        case .missingRemoteURL: "Apple did not provide a downloadable restore image URL."
        case .appleCatalogueUnavailable(let detail):
            "Apple’s restore-image catalogue could not be loaded after several attempts: \(detail)"
        }
    }
}

struct OSMediaDownloadRecord: Identifiable {
    enum State {
        case downloading, completed, failed, cancelled

        var title: String {
            switch self {
            case .downloading: "Downloading"
            case .completed: "Completed"
            case .failed: "Failed"
            case .cancelled: "Cancelled"
            }
        }
    }

    let id: UUID
    let title: String
    let destination: URL
    var progress: Double
    var state: State
    var detail: String

    init(id: UUID = UUID(), title: String, destination: URL, progress: Double, state: State, detail: String) {
        self.id = id
        self.title = title
        self.destination = destination
        self.progress = progress
        self.state = state
        self.detail = detail
    }
}

enum OSMediaSource {
    static let ubuntuARM64Page = URL(string: "https://ubuntu.com/download/server/arm")!
    static let windowsARM64Page = URL(string: "https://www.microsoft.com/en-us/software-download/windows11arm64")!
    static let appleMacOSDownloadPage = URL(string: "https://support.apple.com/en-us/102662")!

    static func isApprovedAppleDownload(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https", let host = url.host?.lowercased() else { return false }
        return host == "apple.com" || host.hasSuffix(".apple.com") ||
            host == "cdn-apple.com" || host.hasSuffix(".cdn-apple.com")
    }
}

@MainActor
final class OSMediaDownloader {
    private var task: Task<Void, Never>?

    var isDownloading: Bool { task != nil }

    func cancel() {
        task?.cancel()
        task = nil
    }

    func downloadLatestMacOSRestoreImage(to destination: URL, progress: @escaping (Double) -> Void,
                                         completion: @escaping (Result<URL, Error>) -> Void) {
        cancel()
        guard destination.isFileURL, destination.pathExtension.lowercased() == "ipsw" else {
            completion(.failure(OSMediaDownloadError.invalidDestination))
            return
        }

        task = Task { [weak self] in
            do {
                var restoreImage: VZMacOSRestoreImage?
                var lastError: Error?
                for attempt in 0..<3 {
                    do {
                        restoreImage = try await VZMacOSRestoreImage.latestSupported
                        break
                    } catch {
                        lastError = error
                        if attempt < 2 {
                            try await Task.sleep(for: .seconds(2 * (attempt + 1)))
                        }
                    }
                }
                guard let restoreImage else {
                    throw OSMediaDownloadError.appleCatalogueUnavailable(lastError?.localizedDescription ?? "Unknown Apple installation-service error.")
                }
                let sourceURL = restoreImage.url
                guard OSMediaSource.isApprovedAppleDownload(sourceURL) else {
                    throw OSMediaDownloadError.missingRemoteURL
                }
                let (bytes, response) = try await URLSession.shared.bytes(from: sourceURL)
                guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                    throw URLError(.badServerResponse)
                }
                let fileManager = FileManager.default
                let parent = destination.deletingLastPathComponent()
                guard fileManager.isWritableFile(atPath: parent.path) else {
                    throw OSMediaDownloadError.invalidDestination
                }
                let staged = parent.appendingPathComponent(".\(destination.lastPathComponent).download")
                try? fileManager.removeItem(at: staged)
                fileManager.createFile(atPath: staged.path, contents: nil)
                let handle = try FileHandle(forWritingTo: staged)
                defer { try? handle.close() }
                let expected = response.expectedContentLength
                var received: Int64 = 0
                var buffer = Data()
                buffer.reserveCapacity(1024 * 1024)
                for try await byte in bytes {
                    try Task.checkCancellation()
                    buffer.append(byte)
                    received += 1
                    if buffer.count >= 1024 * 1024 {
                        try handle.write(contentsOf: buffer)
                        buffer.removeAll(keepingCapacity: true)
                        if expected > 0 { progress(min(0.99, Double(received) / Double(expected))) }
                    }
                }
                if !buffer.isEmpty { try handle.write(contentsOf: buffer) }
                try Task.checkCancellation()
                try? fileManager.removeItem(at: destination)
                try fileManager.moveItem(at: staged, to: destination)
                progress(1)
                completion(.success(destination))
            } catch {
                completion(.failure(error))
            }
            self?.task = nil
        }
    }
}
