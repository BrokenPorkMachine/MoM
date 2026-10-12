import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

struct VMDiskImageInfo {
    let url: URL
    let sizeBytes: UInt64
    let allocatedBytes: UInt64
    let identity: String
    var sizeGiB: Double { Double(sizeBytes) / Double(VMDiskImageStore.gibibyte) }
}

enum VMDiskImageError: LocalizedError {
    case invalidPath, invalidImage, invalidSize, alreadyExists, inUse, shrinkUnsupported, multipleLinks, insufficientSpace
    var errorDescription: String? {
        switch self {
        case .invalidPath: return "Choose a local .img or .raw file outside /dev. Symbolic links are not supported."
        case .invalidImage: return "Choose a regular raw disk image whose size is a positive multiple of 512 bytes."
        case .invalidSize: return "Disk image capacity must be between 1 and 2048 GiB; a managed boot disk needs at least 64 GiB."
        case .alreadyExists: return "A file already exists at this destination. Choose a new filename."
        case .inUse: return "This disk image is in use. Stop every VM using it before changing it."
        case .shrinkUnsupported: return "Choose a larger capacity. Shrinking an image can destroy partitions and is not supported."
        case .multipleLinks: return "This image has multiple hard links. Use an independent copy before modifying it."
        case .insufficientSpace: return "The selected volume does not have enough headroom for this disk image operation."
        }
    }
}

/// Advisory locks are held for a VM's entire session, including installation.
final class VMDiskImageLease {
    let descriptor: Int32
    let info: VMDiskImageInfo
    private let lockDescriptor: Int32
    init(url: URL, writable: Bool = false) throws {
        let checked = try VMDiskImageStore.checkedURL(url)
        descriptor = open(checked.path, (writable ? O_RDWR : O_RDONLY) | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard descriptor >= 0 else { throw VMDiskImageStore.posixError() }
        do {
            info = try VMDiskImageStore.inspect(descriptor, url: checked)
            // VZ takes its own lock on the image when starting. Use a separate, per-inode
            // lock for VolumeBoot sessions so its lock does not conflict with ours.
            lockDescriptor = try VMDiskImageStore.openSessionLock(identity: info.identity)
        } catch {
            close(descriptor)
            throw error
        }
    }
    deinit { close(lockDescriptor); close(descriptor) }
}

enum VMDiskImageStore {
    static let gibibyte: UInt64 = 1_073_741_824
    static let maximumBytes = 2048 * gibibyte

    fileprivate static func openSessionLock(identity: String) throws -> Int32 {
        #if canImport(Darwin)
        let base = URL(fileURLWithPath: "/private/tmp")
        #else
        let base = FileManager.default.temporaryDirectory
        #endif
        let directory = base.appendingPathComponent("VolumeBootDiskLocks-\(getuid())")
        if !FileManager.default.fileExists(atPath: directory.path) {
            do { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700]) }
            catch {
                if !FileManager.default.fileExists(atPath: directory.path) { throw error }
            }
        }
        var directoryInfo = stat()
        guard lstat(directory.path, &directoryInfo) == 0,
              directoryInfo.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR), directoryInfo.st_uid == getuid(),
              directoryInfo.st_mode & 0o077 == 0 else { throw VMDiskImageError.invalidPath }
        let lockURL = directory.appendingPathComponent(identity + ".lock")
        let lock = open(lockURL.path, O_RDWR | O_CREAT | O_NOFOLLOW | O_CLOEXEC, mode_t(0o600))
        guard lock >= 0 else { throw posixError() }
        var attributes = stat()
        guard fstat(lock, &attributes) == 0, attributes.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG),
              attributes.st_uid == getuid(), attributes.st_nlink == 1,
              flock(lock, LOCK_EX | LOCK_NB) == 0 else { close(lock); throw VMDiskImageError.inUse }
        // Do not unlink released locks: another process may already have opened the inode.
        return lock
    }

    static func checkedURL(_ url: URL) throws -> URL {
        guard url.isFileURL, url.path.hasPrefix("/"), ["img", "raw"].contains(url.pathExtension.lowercased()) else {
            throw VMDiskImageError.invalidPath
        }
        let standardized = url.standardizedFileURL
        let resolved = standardized.resolvingSymlinksInPath()
        guard standardized.path == resolved.path, resolved.path != "/dev", !resolved.path.hasPrefix("/dev/") else {
            throw VMDiskImageError.invalidPath
        }
        return resolved
    }

    static func inspect(_ descriptor: Int32, url: URL) throws -> VMDiskImageInfo {
        var attributes = stat()
        guard fstat(descriptor, &attributes) == 0 else { throw posixError() }
        guard attributes.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG), attributes.st_size > 0,
              attributes.st_size % 512 == 0, UInt64(attributes.st_size) <= maximumBytes else {
            throw VMDiskImageError.invalidImage
        }
        return VMDiskImageInfo(url: url, sizeBytes: UInt64(attributes.st_size),
            allocatedBytes: UInt64(max(0, attributes.st_blocks)) * 512,
            identity: "\(attributes.st_dev):\(attributes.st_ino)")
    }

    static func inspect(at url: URL) throws -> VMDiskImageInfo {
        let checked = try checkedURL(url)
        let descriptor = open(checked.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard descriptor >= 0 else { throw posixError() }
        defer { close(descriptor) }
        return try inspect(descriptor, url: checked)
    }

    static func capacityBytes(_ sizeGiB: Int, bootDisk: Bool = false) throws -> UInt64 {
        guard (bootDisk ? 64 : 1)...2048 ~= sizeGiB else { throw VMDiskImageError.invalidSize }
        return UInt64(sizeGiB) * gibibyte
    }

    @discardableResult
    static func create(at url: URL, sizeGiB: Int) throws -> VMDiskImageInfo {
        let checked = try checkedURL(url)
        let bytes = try capacityBytes(sizeGiB)
        try requireHeadroom(for: checked, additionalBytes: bytes)
        let descriptor = open(checked.path, O_RDWR | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, mode_t(0o600))
        guard descriptor >= 0 else {
            if errno == EEXIST { throw VMDiskImageError.alreadyExists }
            throw posixError()
        }
        defer { close(descriptor) }
        do {
            guard ftruncate(descriptor, off_t(bytes)) == 0, fsync(descriptor) == 0 else { throw posixError() }
            return try inspect(descriptor, url: checked)
        } catch {
            // Only remove the new file if its pathname still identifies our descriptor.
            if (try? verifyUnchangedPath(descriptor, url: checked)) != nil { unlink(checked.path) }
            throw error
        }
    }

    @discardableResult
    static func grow(at url: URL, toGiB sizeGiB: Int) throws -> VMDiskImageInfo {
        let bytes = try capacityBytes(sizeGiB)
        let lease = try VMDiskImageLease(url: url, writable: true)
        guard flock(lease.descriptor, LOCK_EX | LOCK_NB) == 0 else { throw VMDiskImageError.inUse }
        guard bytes > lease.info.sizeBytes else { throw VMDiskImageError.shrinkUnsupported }
        try requireHeadroom(for: lease.info.url, additionalBytes: bytes - lease.info.sizeBytes)
        try verifyUnchangedPath(lease.descriptor, url: lease.info.url)
        guard ftruncate(lease.descriptor, off_t(bytes)) == 0, fsync(lease.descriptor) == 0 else { throw posixError() }
        return try inspect(lease.descriptor, url: lease.info.url)
    }

    static func delete(at url: URL) throws {
        try delete(try VMDiskImageLease(url: url))
    }

    static func delete(_ lease: VMDiskImageLease) throws {
        guard flock(lease.descriptor, LOCK_EX | LOCK_NB) == 0 else { throw VMDiskImageError.inUse }
        try verifyUnchangedPath(lease.descriptor, url: lease.info.url)
        guard unlink(lease.info.url.path) == 0 else { throw posixError() }
    }

    private static func verifyUnchangedPath(_ descriptor: Int32, url: URL) throws {
        var opened = stat(), named = stat()
        guard fstat(descriptor, &opened) == 0, lstat(url.path, &named) == 0 else { throw posixError() }
        guard opened.st_dev == named.st_dev, opened.st_ino == named.st_ino,
              named.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG) else { throw VMDiskImageError.invalidPath }
        guard opened.st_nlink == 1 else { throw VMDiskImageError.multipleLinks }
    }

    private static func requireHeadroom(for url: URL, additionalBytes: UInt64) throws {
        let volume = url.deletingLastPathComponent()
        if ProcessInfo.processInfo.environment["MACONMAC_ALLOW_LOW_SPACE_TEST"] != "1",
           let available = try volume.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage,
           available < Int64(min(UInt64(Int64.max), additionalBytes > 0 ? 1 * 1024 * 1024 : 0)) {
            throw VMDiskImageError.insufficientSpace
        }
    }

    static func posixError() -> NSError { NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
}
