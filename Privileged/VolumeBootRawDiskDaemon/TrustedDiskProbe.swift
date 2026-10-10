import Foundation
import DiskArbitration
import IOKit
import Darwin

/// Read-only metadata collection for a disposable, unpartitioned external disk.
/// This is deliberately NOT an APFS ownership analyzer. A nonempty partition
/// map, any missing field, or any discrepancy between before/after scans denies.
enum TrustedDiskProbe {
    enum Denied: LocalizedError {
        case invalid(String)
        var errorDescription: String? {
            if case .invalid(let why) = self { return why }
            return "Device denied"
        }
    }

    private static func plist(_ args: [String]) throws -> [String: Any] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0, data.count <= 4_194_304,
              let value = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            throw Denied.invalid("diskutil metadata unavailable")
        }
        return value
    }

    private static func registryID(_ name: String) throws -> UInt64 {
        guard let session = DASessionCreate(kCFAllocatorDefault) else {
            throw Denied.invalid("DiskArbitration session unavailable")
        }
        let disk = name.withCString { DADiskCreateFromBSDName(kCFAllocatorDefault, session, $0) }
        guard let disk else { throw Denied.invalid("DiskArbitration disk missing") }
        let media = DADiskCopyIOMedia(disk)
        guard media != 0 else { throw Denied.invalid("IOKit media unavailable") }
        defer { IOObjectRelease(media) }
        var id: UInt64 = 0
        guard IORegistryEntryGetRegistryEntryID(media, &id) == KERN_SUCCESS, id != 0 else {
            throw Denied.invalid("IOKit identity missing")
        }
        return id
    }

    static func snapshot(_ name: String) throws -> ReadOnlyGrantSnapshot {
        guard BrokerAuthorizationPolicy.isValidBSDName(name) else {
            throw Denied.invalid("Invalid whole-disk identifier")
        }
        let detail = try plist(["info", "-plist", name])
        let listing = try plist(["list", "-plist"])
        guard let disks = listing["AllDisksAndPartitions"] as? [[String: Any]],
              let entry = disks.first(where: { $0["DeviceIdentifier"] as? String == name }) else {
            throw Denied.invalid("Disk topology unavailable")
        }
        // Unknown fields are NOT treated as an empty partition map.
        let partitions = entry["Partitions"] as? [[String: Any]]
        let count: Int? = partitions?.count ?? ((entry["Partitions"] == nil) ? 0 : nil)
        let content = (detail["Content"] as? String ?? "").lowercased()
        let entryContent = (entry["Content"] as? String ?? "").lowercased()
        let apfs = [content, entryContent].contains(where: { $0.contains("apfs") }) ||
                   partitions?.contains(where: { ($0["Content"] as? String ?? "").lowercased().contains("apfs") }) == true
        let fsKeys = ["FilesystemName", "FilesystemType", "FilesystemUserVisibleName", "VolumeName", "APFSContainerReference"]
        let fs = fsKeys.contains { key in
            guard let v = detail[key] else { return false }
            if let str = v as? String { return !str.isEmpty }
            return true
        }
        let size = (detail["TotalSize"] as? NSNumber)?.uint64Value
        let physical = (detail["VirtualOrPhysical"] as? String).map { $0 == "Physical" }
        let location = (detail["DeviceLocation"] as? String).map { $0 == "External" }
        let mounted = detail["Mounted"] as? Bool
        return ReadOnlyGrantSnapshot(
            requestedBSD: name, reportedBSD: detail["DeviceIdentifier"] as? String ?? "",
            wholeDisk: detail["WholeDisk"] as? Bool,
            internalMedia: detail["Internal"] as? Bool,
            physicalMedia: physical, externalLocation: location, mounted: mounted,
            partitionCount: count, anyAPFS: apfs, hasFilesystem: fs,
            sizeBytes: size, mediaRegistryID: try registryID(name)
        )
    }

    static func openVerifiedReadOnly(_ name: String) throws -> FileHandle {
        let before = try snapshot(name)
        let reasons = ReadOnlyGrantPolicy.denialReasons(before)
        guard reasons.isEmpty else { throw Denied.invalid(reasons.joined(separator: "; ")) }
        let path = "/dev/r" + name
        let fd = open(path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK)
        guard fd >= 0 else { throw Denied.invalid("Read-only open denied by OS") }
        var retained = false
        defer { if !retained { _ = Darwin.close(fd) } }
        var fileStat = stat()
        var pathStat = stat()
        guard fstat(fd, &fileStat) == 0,
              lstat(path, &pathStat) == 0,
              (fileStat.st_mode & mode_t(S_IFMT)) == mode_t(S_IFCHR),
              (pathStat.st_mode & mode_t(S_IFMT)) == mode_t(S_IFCHR),
              fileStat.st_rdev == pathStat.st_rdev,
              fcntl(fd, F_GETFL) & O_ACCMODE == O_RDONLY else {
            throw Denied.invalid("Descriptor identity or access mode mismatch")
        }
        let after = try snapshot(name)
        guard before == after, ReadOnlyGrantPolicy.allowed(after) else {
            throw Denied.invalid("Disk changed between metadata checks")
        }
        retained = true
        return FileHandle(fileDescriptor: fd, closeOnDealloc: true)
    }
}
