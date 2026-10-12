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

    /// Streams a new file into an exclusive partial, syncs it, then publishes it
    /// without replacing an existing name.
    static func writeStreamedFile(partialName: String, finalName: String, root: URL,
                                  component: String, writeBody: (Int32) throws -> Void) throws {
        let directoryFD = try openDirectory(root: root, component: component)
        defer { close(directoryFD) }
        var fileFD = openat(directoryFD, partialName, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, mode_t(0o600))
        guard fileFD >= 0 else { throw CocoaError(.fileWriteNoPermission) }
        do {
            try writeBody(fileFD)
            guard fsync(fileFD) == 0 else { throw CocoaError(.fileWriteUnknown) }
            guard close(fileFD) == 0 else { fileFD = -1; throw CocoaError(.fileWriteUnknown) }
            fileFD = -1
            guard linkat(directoryFD, partialName, directoryFD, finalName, 0) == 0 else { throw CocoaError(.fileWriteFileExists) }
            guard unlinkat(directoryFD, partialName, 0) == 0 else {
                _ = unlinkat(directoryFD, finalName, 0)
                throw CocoaError(.fileWriteUnknown)
            }
            _ = fsync(directoryFD)
        } catch {
            if fileFD >= 0 { _ = close(fileFD) }
            _ = unlinkat(directoryFD, partialName, 0)
            throw error
        }
    }

    static func writeStreamedFile(partialName: String, finalName: String, in directory: URL,
                                  writeBody: (Int32) throws -> Void) throws {
        let directoryFD = open(directory.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard directoryFD >= 0 else { throw CocoaError(.fileWriteNoPermission) }
        defer { close(directoryFD) }
        var fileFD = openat(directoryFD, partialName, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, mode_t(0o600))
        guard fileFD >= 0 else { throw CocoaError(.fileWriteFileExists) }
        do {
            try writeBody(fileFD)
            guard fsync(fileFD) == 0 else { throw CocoaError(.fileWriteUnknown) }
            guard close(fileFD) == 0 else { fileFD = -1; throw CocoaError(.fileWriteUnknown) }
            fileFD = -1
            guard linkat(directoryFD, partialName, directoryFD, finalName, 0) == 0 else { throw CocoaError(.fileWriteFileExists) }
            guard unlinkat(directoryFD, partialName, 0) == 0 else {
                _ = unlinkat(directoryFD, finalName, 0); throw CocoaError(.fileWriteUnknown)
            }
            _ = fsync(directoryFD)
        } catch {
            if fileFD >= 0 { _ = close(fileFD) }
            _ = unlinkat(directoryFD, partialName, 0)
            throw error
        }
    }

    static func writeAll(_ data: Data, to fd: Int32) throws {
        try data.withUnsafeBytes { bytes in
            guard let base = bytes.baseAddress else { return }
            var offset = 0
            while offset < bytes.count {
                let result = write(fd, base.advanced(by: offset), bytes.count - offset)
                if result < 0 && errno == EINTR { continue }
                guard result > 0 else { throw CocoaError(.fileWriteUnknown) }
                offset += result
            }
        }
    }

    static func streamRegularFile(_ source: URL, maximumBytes: UInt64, chunkSize: Int,
                                  consume: (Data) throws -> Void) throws -> UInt64 {
        let fd = open(source.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
        guard fd >= 0 else { throw CocoaError(.fileReadNoPermission) }
        var before = stat()
        guard fstat(fd, &before) == 0, (before.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG), before.st_size >= 0,
              UInt64(before.st_size) <= maximumBytes else {
            close(fd); throw CocoaError(.fileReadTooLarge)
        }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        defer { try? handle.close() }
        var total: UInt64 = 0
        while total < UInt64(before.st_size) {
            let chunk = try handle.read(upToCount: min(chunkSize, Int(UInt64(before.st_size) - total))) ?? Data()
            guard !chunk.isEmpty else { throw CocoaError(.fileReadCorruptFile) }
            try consume(chunk)
            total += UInt64(chunk.count)
        }
        guard (try handle.read(upToCount: 1) ?? Data()).isEmpty else { throw CocoaError(.fileReadTooLarge) }
        var after = stat()
        guard fstat(fd, &after) == 0, before.st_dev == after.st_dev, before.st_ino == after.st_ino,
              before.st_size == after.st_size else { throw CocoaError(.fileReadCorruptFile) }
        return total
    }

    static func withExclusiveDirectoryLock<T>(root: URL, component: String, _ body: () throws -> T) throws -> T {
        let directoryFD = try openDirectory(root: root, component: component)
        defer { close(directoryFD) }
        let lockFD = openat(directoryFD, ".quota.lock", O_RDWR | O_CREAT | O_NOFOLLOW, mode_t(0o600))
        guard lockFD >= 0 else { throw CocoaError(.fileWriteNoPermission) }
        defer { close(lockFD) }
        guard flock(lockFD, LOCK_EX) == 0 else { throw CocoaError(.fileWriteUnknown) }
        defer { _ = flock(lockFD, LOCK_UN) }
        return try body()
    }

    /// Removes expired regular files, then evicts oldest entries until both
    /// directory quotas hold. Symlinks and non-regular nodes are left untouched.
    @discardableResult
    static func prune(root: URL, component: String, olderThan expiry: Date,
                      maxFiles: Int, maxBytes: UInt64) throws -> (files: Int, bytes: UInt64) {
        let directoryFD = try openDirectory(root: root, component: component)
        defer { close(directoryFD) }
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent(component).path) else {
            throw CocoaError(.fileReadNoPermission)
        }
        var entries: [(name: String, size: UInt64, modified: Date)] = []
        for name in names where name != ".quota.lock" {
            var info = stat()
            guard fstatat(directoryFD, name, &info, AT_SYMLINK_NOFOLLOW) == 0,
                  (info.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG), info.st_size >= 0 else { continue }
            if name.hasSuffix(".partial") {
                _ = unlinkat(directoryFD, name, 0)
                continue
            }
            #if canImport(Darwin)
            let modified = Date(timeIntervalSince1970: TimeInterval(info.st_mtimespec.tv_sec) + TimeInterval(info.st_mtimespec.tv_nsec) / 1_000_000_000)
            #else
            let modified = Date(timeIntervalSince1970: TimeInterval(info.st_mtim.tv_sec) + TimeInterval(info.st_mtim.tv_nsec) / 1_000_000_000)
            #endif
            if modified < expiry {
                _ = unlinkat(directoryFD, name, 0)
            } else {
                entries.append((name, UInt64(info.st_size), modified))
            }
        }
        entries.sort { $0.modified > $1.modified }
        var kept: [(name: String, size: UInt64, modified: Date)] = []
        var total: UInt64 = 0
        for entry in entries {
            if kept.count >= maxFiles || entry.size > maxBytes || total > maxBytes - entry.size {
                _ = unlinkat(directoryFD, entry.name, 0)
            } else {
                kept.append(entry); total += entry.size
            }
        }
        _ = fsync(directoryFD)
        return (kept.count, total)
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
    static let maxRetainedMessagesPerDirection = 500
    static let maxRetainedMessageBytesPerDirection: UInt64 = 8 * 1024 * 1024
    static let messageRetention: TimeInterval = 7 * 24 * 60 * 60
    static let maxRetainedFilesPerDirection = 100
    static let maxRetainedFileBytesPerDirection: UInt64 = 256 * 1024 * 1024
    static let fileRetention: TimeInterval = 7 * 24 * 60 * 60

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
        try VBGuestFileIO.withExclusiveDirectoryLock(root: exchangeRoot, component: component) {
            let expiresBefore = Date().addingTimeInterval(-messageRetention)
            let usage = try VBGuestFileIO.prune(root: exchangeRoot, component: component, olderThan: expiresBefore,
                maxFiles: maxRetainedMessagesPerDirection, maxBytes: maxRetainedMessageBytesPerDirection)
            let record = VBExchangeMessage(id: UUID(), timestamp: Date(), from: origin, body: message)
            let data = try JSONEncoder().encode(record)
            guard usage.files < maxRetainedMessagesPerDirection,
                  usage.bytes <= maxRetainedMessageBytesPerDirection - UInt64(data.count) else {
                throw NSError(domain: "VolumeBoot.Exchange", code: 4, userInfo: [NSLocalizedDescriptionKey: "Message retention quota is full; remove old exchange messages first."])
            }
            try VBGuestFileIO.writeNewFile(data, name: "\(record.id.uuidString).json", root: exchangeRoot, component: component)
        }
    }

    static func receive(for recipient: String, in vmFolder: URL, limit: Int = 100) -> [VBExchangeMessage] {
        let component = recipient == "host" ? "guest-to-host" : "host-to-guest"
        let exchangeRoot = root(for: vmFolder)
        let dir = exchangeRoot.appendingPathComponent(component, isDirectory: true)
        guard isSafeDirectory(root(for: vmFolder)), isSafeDirectory(dir) else { return [] }
        let pruned = try? VBGuestFileIO.withExclusiveDirectoryLock(root: exchangeRoot, component: component) {
            try VBGuestFileIO.prune(root: exchangeRoot, component: component,
                olderThan: Date().addingTimeInterval(-messageRetention), maxFiles: maxRetainedMessagesPerDirection,
                maxBytes: maxRetainedMessageBytesPerDirection)
        }
        guard pruned != nil, let urls = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles]) else { return [] }
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
        let exchangeRoot = root(for: vmFolder)
        let component = origin == "host" ? "host-files" : "guest-files"
        try VBGuestFileIO.withExclusiveDirectoryLock(root: exchangeRoot, component: component) {
            let usage = try VBGuestFileIO.prune(root: exchangeRoot, component: component,
                olderThan: Date().addingTimeInterval(-fileRetention), maxFiles: maxRetainedFilesPerDirection,
                maxBytes: maxRetainedFileBytesPerDirection)
            guard usage.files < maxRetainedFilesPerDirection,
                  usage.bytes <= maxRetainedFileBytesPerDirection - UInt64(size) else {
                throw NSError(domain: "VolumeBoot.Exchange", code: 4, userInfo: [NSLocalizedDescriptionKey: "File retention quota is full"])
            }
            try VBGuestFileIO.writeStreamedFile(partialName: filename + ".partial", finalName: filename, root: exchangeRoot, component: component) { fd in
                let copied = try VBGuestFileIO.streamRegularFile(source, maximumBytes: maxFileBytes, chunkSize: 128 * 1024) {
                    try VBGuestFileIO.writeAll($0, to: fd)
                }
                guard copied == UInt64(size) else { throw CocoaError(.fileReadCorruptFile) }
            }
        }
        return directory.appendingPathComponent(filename)
    }
}
