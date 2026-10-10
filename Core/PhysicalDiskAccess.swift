import Foundation
import Virtualization
import Darwin

/// Device snapshots are advisory. An attachment must always be revalidated immediately
/// before opening, using a trusted broker, to defeat diskN reuse and hot-unplug races.
struct PhysicalDiskIdentity: Codable, Hashable, Sendable {
    let bsdName: String
    let wholeDiskBSDName: String
    let mediaUUID: String
    let sizeBytes: UInt64
    let isInternal: Bool
    let isWholeDisk: Bool
}

struct ReadOnlyDiskLeaseRequest: Codable, Sendable {
    let identity: PhysicalDiskIdentity
    let sessionID: UUID
}

enum PhysicalDiskError: LocalizedError {
    case invalidBSDName, identityMismatch, permissionDenied, unsupportedBroker
    case readOnlyRequired, alreadyLeased, invalidDescriptor, activeSystemDisk, permissionDeniedWithReason(String)
    var errorDescription: String? {
        switch self {
        case .invalidBSDName: return "Invalid BSD disk identifier"
        case .identityMismatch: return "The physical disk has changed since inspection"
        case .permissionDenied: return "Opening the block device requires approved privileged access"
        case .permissionDeniedWithReason(let reason): return reason.isEmpty ? "Disk grant refused by broker" : reason
        case .unsupportedBroker: return "The signed privileged disk broker is not installed or enabled"
        case .readOnlyRequired: return "Physical disk attachments must be read-only"
        case .alreadyLeased: return "This device already has an active lease"
        case .invalidDescriptor: return "The granted file descriptor is invalid or writable"
        case .activeSystemDisk: return "Host system storage cannot be assigned to the guest"
        }
    }
}

/// A file descriptor transferred through a broker becomes a guest-visible disk ONLY after
/// the broker has checked stable identity, complete APFS topology, and host-system ownership.
/// This type never opens a /dev node or elevates privileges.
@MainActor
final class ReadOnlyPhysicalDiskLease {
    let identity: PhysicalDiskIdentity
    let sessionID: UUID
    private(set) var handle: FileHandle

    init(identity: PhysicalDiskIdentity, sessionID: UUID, transferredDescriptor fd: Int32) throws {
        guard Self.validBSDName(identity.bsdName), Self.validBSDName(identity.wholeDiskBSDName) else {
            throw PhysicalDiskError.invalidBSDName
        }
        guard fd >= 0 else { throw PhysicalDiskError.invalidDescriptor }
        let flags = fcntl(fd, F_GETFL)
        guard flags >= 0, flags & O_ACCMODE == O_RDONLY else { throw PhysicalDiskError.invalidDescriptor }
        let copy = dup(fd)
        guard copy >= 0 else { throw PhysicalDiskError.invalidDescriptor }
        self.identity = identity
        self.sessionID = sessionID
        self.handle = FileHandle(fileDescriptor: copy, closeOnDealloc: true)
    }

    static func validBSDName(_ name: String) -> Bool {
        // Never accept paths, whitespace, or arbitrary filesystem names.
        name.range(of: #"^disk[0-9]+(s[0-9]+)?$"#, options: .regularExpression) != nil
    }

    func makeDevice() throws -> VZVirtioBlockDeviceConfiguration {
        let attachment = try VZDiskBlockDeviceStorageDeviceAttachment(
            fileHandle: handle, readOnly: true, synchronizationMode: .full
        )
        return VZVirtioBlockDeviceConfiguration(attachment: attachment)
    }

    func close() throws { try handle.close() }
}

/// Wire contract for the future hardened, signed XPC service. There is deliberately
/// no permissive fallback from broker failure to direct raw-device open().
protocol PhysicalDiskLeaseBroker {
    func authorizeReadOnly(_ request: ReadOnlyDiskLeaseRequest) async throws -> ReadOnlyPhysicalDiskLease
    func release(sessionID: UUID) async
}

@MainActor
struct DisabledPhysicalDiskLeaseBroker: PhysicalDiskLeaseBroker {
    func authorizeReadOnly(_ request: ReadOnlyDiskLeaseRequest) async throws -> ReadOnlyPhysicalDiskLease {
        throw PhysicalDiskError.unsupportedBroker
    }
    func release(sessionID: UUID) async {}
}
