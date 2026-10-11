import Foundation

#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

enum VBGuestFileIO {
    static func openDirectory(root: URL, component: String? = nil) throws -> Int32 {
        let rootFD = open(root.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard rootFD >= 0 else { throw CocoaError(.fileReadNoPermission) }
        guard let component else { return rootFD }
        defer { close(rootFD) }
        let componentFD = openat(rootFD, component, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard componentFD >= 0 else { throw CocoaError(.fileReadNoPermission) }
        return componentFD
    }

    static func writeNewFile(_ data: Data, name: String, root: URL, component: String? = nil) throws {
        let directoryFD = try openDirectory(root: root, component: component)
        defer { close(directoryFD) }
        let fileFD = openat(directoryFD, name, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, mode_t(0o600))
        guard fileFD >= 0 else { throw CocoaError(.fileWriteNoPermission) }
        do {
            let handle = FileHandle(fileDescriptor: fileFD, closeOnDealloc: true)
            try handle.write(contentsOf: data)
            try handle.synchronize()
        } catch {
            _ = unlinkat(directoryFD, name, 0)
            throw error
        }
    }

    static func readBoundedFile(name: String, root: URL, component: String? = nil, limit: Int) throws -> Data {
        let directoryFD = try openDirectory(root: root, component: component)
        defer { close(directoryFD) }
        let fileFD = openat(directoryFD, name, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        guard fileFD >= 0 else { throw CocoaError(.fileReadNoPermission) }
        var info = stat()
        guard fstat(fileFD, &info) == 0, (info.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG) else {
            close(fileFD)
            throw CocoaError(.fileReadNoPermission)
        }
        let handle = FileHandle(fileDescriptor: fileFD, closeOnDealloc: true)
        return try handle.read(upToCount: limit + 1) ?? Data()
    }

    static func removeFile(name: String, root: URL, component: String? = nil) throws {
        let directoryFD = try openDirectory(root: root, component: component)
        defer { close(directoryFD) }
        guard unlinkat(directoryFD, name, 0) == 0 else { throw CocoaError(.fileNoSuchFile) }
    }
}

/// Deliberately narrow data-only protocol. No guest or host remote command execution.
struct VBExchangeMessage: Codable, Identifiable {
    let id: UUID
    let timestamp: Date
    let from: String
    let body: String
}

struct VBGuestHeartbeat: Codable {
    let protocolVersion: Int
    let timestamp: Date
    let hostname: String
    let operatingSystem: String
}

enum HostGuestExchange {
    static let rootName = "Exchange"
    static let maxMessageBytes = 16_384
    static let maxFileBytes: UInt64 = 64 * 1024 * 1024

    static func root(for vmFolder: URL) -> URL { vmFolder.appendingPathComponent(rootName, isDirectory: true) }

    static func createIfNeeded(in vmFolder: URL) throws {
        let root = root(for: vmFolder)
        try ensureDirectory(root)
        for component in ["host-to-guest", "guest-to-host", "host-files", "guest-files"] {
            try ensureDirectory(root.appendingPathComponent(component, isDirectory: true))
        }
    }

    private static func ensureDirectory(_ url: URL) throws {
        if !FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        }
        guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
              values.isDirectory == true, values.isSymbolicLink != true else {
            throw CocoaError(.fileWriteFileExists)
        }
    }

    private static func isSafeDirectory(_ url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
              values.isDirectory == true, values.isSymbolicLink != true else { return false }
        return true
    }

    static func send(_ message: String, from origin: String, in vmFolder: URL) throws {
        guard origin == "host" || origin == "guest" else { throw NSError(domain: "VolumeBoot.Exchange", code: 1) }
        guard !message.isEmpty, message.utf8.count <= maxMessageBytes else { throw NSError(domain: "VolumeBoot.Exchange", code: 2) }
        let exchangeRoot = root(for: vmFolder)
        let component = origin == "host" ? "host-to-guest" : "guest-to-host"
        let dir = exchangeRoot.appendingPathComponent(component, isDirectory: true)
        guard isSafeDirectory(root(for: vmFolder)), isSafeDirectory(dir) else { throw CocoaError(.fileWriteInvalidFileName) }
        let record = VBExchangeMessage(id: UUID(), timestamp: Date(), from: origin, body: message)
        try VBGuestFileIO.writeNewFile(JSONEncoder().encode(record), name: "\(record.id.uuidString).json", root: exchangeRoot, component: component)
    }

    static func receive(for recipient: String, in vmFolder: URL, limit: Int = 100) -> [VBExchangeMessage] {
        let dir = root(for: vmFolder).appendingPathComponent(recipient == "host" ? "guest-to-host" : "host-to-guest", isDirectory: true)
        guard isSafeDirectory(root(for: vmFolder)), isSafeDirectory(dir),
              let urls = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles]) else { return [] }
        return urls.filter { $0.pathExtension == "json" && UUID(uuidString: $0.deletingPathExtension().lastPathComponent) != nil }
            .prefix(max(0, min(limit, 500)))
            .compactMap { url in
                guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]),
                      values.isRegularFile == true, values.isSymbolicLink != true,
                      (values.fileSize ?? Int.max) <= maxMessageBytes + 2_048,
                      let data = try? VBGuestFileIO.readBoundedFile(name: url.lastPathComponent, root: root(for: vmFolder), component: recipient == "host" ? "guest-to-host" : "host-to-guest", limit: maxMessageBytes + 2_048),
                      data.count <= maxMessageBytes + 2_048 else { return nil }
                return try? JSONDecoder().decode(VBExchangeMessage.self, from: data)
            }.sorted { $0.timestamp > $1.timestamp }
    }

    static func guestHeartbeat(in vmFolder: URL) -> VBGuestHeartbeat? {
        let url = root(for: vmFolder).appendingPathComponent("heartbeat.json")
        guard isSafeDirectory(root(for: vmFolder)),
              let data = try? VBGuestFileIO.readBoundedFile(name: url.lastPathComponent, root: root(for: vmFolder), limit: 4_096),
              data.count <= 4_096 else { return nil }
        return try? JSONDecoder().decode(VBGuestHeartbeat.self, from: data)
    }

    /// Filename is a UUID, never a user-provided basename, to avoid traversal.
    static func stageFile(_ source: URL, from origin: String, in vmFolder: URL) throws -> URL {
        guard origin == "host" || origin == "guest" else { throw NSError(domain: "VolumeBoot.Exchange", code: 2) }
        let values = try source.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .isSymbolicLinkKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true,
              let size = values.fileSize, size >= 0, UInt64(size) <= maxFileBytes else { throw NSError(domain: "VolumeBoot.Exchange", code: 3) }
        let directory = root(for: vmFolder).appendingPathComponent(origin == "host" ? "host-files" : "guest-files", isDirectory: true)
        guard isSafeDirectory(root(for: vmFolder)), isSafeDirectory(directory) else { throw CocoaError(.fileWriteInvalidFileName) }
        let extensionText = source.pathExtension.lowercased()
        let safeExt = extensionText.range(of: "^[a-z0-9]{1,12}$", options: .regularExpression) != nil ? ".\(extensionText)" : ""
        let filename = UUID().uuidString + safeExt
        let reader = try FileHandle(forReadingFrom: source)
        defer { try? reader.close() }
        let data = try reader.read(upToCount: Int(size) + 1) ?? Data()
        guard data.count == size else { throw CocoaError(.fileReadTooLarge) }
        try VBGuestFileIO.writeNewFile(data, name: filename, root: root(for: vmFolder), component: origin == "host" ? "host-files" : "guest-files")
        return directory.appendingPathComponent(filename)
    }
}
