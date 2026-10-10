import Foundation

/// Security-critical, pure gate. The daemon must derive EVERY field itself from
/// OS metadata; no user-supplied eligibility flags or device paths are accepted.
/// v0.13 allows only empty, external, unmounted whole physical media.
struct ReadOnlyGrantSnapshot: Equatable {
    let requestedBSD: String
    let reportedBSD: String
    let wholeDisk: Bool?
    let internalMedia: Bool?
    let physicalMedia: Bool?
    let externalLocation: Bool?
    let mounted: Bool?
    let partitionCount: Int?
    let anyAPFS: Bool?
    let hasFilesystem: Bool?
    let sizeBytes: UInt64?
    let mediaRegistryID: UInt64?
}

enum ReadOnlyGrantPolicy {
    static func denialReasons(_ s: ReadOnlyGrantSnapshot) -> [String] {
        var reasons: [String] = []
        if !BrokerAuthorizationPolicy.isValidBSDName(s.requestedBSD) || s.reportedBSD != s.requestedBSD {
            reasons.append("Device identifier invalid or changed")
        }
        if s.wholeDisk != true { reasons.append("Only whole disks supported") }
        if s.internalMedia != false { reasons.append("Internal/unknown media prohibited") }
        if s.physicalMedia != true { reasons.append("Virtual/unknown media prohibited") }
        if s.externalLocation != true { reasons.append("Device location must be external") }
        if s.mounted != false { reasons.append("Mounted/unknown media prohibited") }
        if s.partitionCount != 0 { reasons.append("Partitioned/unknown disks denied in this release") }
        if s.anyAPFS != false { reasons.append("APFS/unknown topology prohibited") }
        if s.hasFilesystem != false { reasons.append("Existing or unknown filesystem prohibited") }
        if s.sizeBytes == nil || s.sizeBytes == 0 { reasons.append("Size unavailable") }
        if s.mediaRegistryID == nil || s.mediaRegistryID == 0 { reasons.append("Stable IOKit registry identity unavailable") }
        return reasons
    }
    static func allowed(_ snapshot: ReadOnlyGrantSnapshot) -> Bool { denialReasons(snapshot).isEmpty }
}

/// Connection ownership means an individual connection may own at most one
/// grant; a disk cannot be granted to a second session concurrently.
final class DiskGrantReservations {
    private let lock = NSLock()
    private var owners: [String: UUID] = [:]

    func reserve(_ disk: String, for session: UUID) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard owners[disk] == nil else { return false }
        owners[disk] = session
        return true
    }
    func release(_ disk: String, for session: UUID) {
        lock.lock(); defer { lock.unlock() }
        if owners[disk] == session { owners.removeValue(forKey: disk) }
    }
    func isReserved(_ disk: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return owners[disk] != nil
    }
}
