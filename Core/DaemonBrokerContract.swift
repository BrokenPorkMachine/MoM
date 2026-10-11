import Foundation

/// Public contract for the separately signed launchd daemon.
/// Transfer of read-only file handles is restricted to empty external test media.
#if canImport(ObjectiveC)
@objc protocol VolumeBootPrivilegedDaemonProtocol {
    func healthReport(withReply reply: @escaping (String) -> Void)
    func readOnlyGrantStatus(_ wholeDiskBSDName: String, withReply reply: @escaping (String) -> Void)
    func readOnlyTopology(_ wholeDiskBSDName: String, withReply reply: @escaping (String) -> Void)
    func requestReadOnlyDisk(_ wholeDiskBSDName: String, withReply reply: @escaping (FileHandle?, String, String) -> Void)
    func releaseReadOnlyDisk(_ leaseID: String, withReply reply: @escaping (Bool) -> Void)
}
#endif

enum DaemonBrokerContract {
    static let protocolVersion = 3
    static let releaseVersion = "0.14.0"
    static let machService = "ca.zensoftware.MacOnMac.RawDiskBroker"
    static let daemonPlist = machService + ".plist"
    static let mainAppBundleID = "ca.zensoftware.MacOnMac"
    static let daemonExecutable = "VolumeBootRawDiskDaemon"
    static let maxPayloadBytes = 4_096

    enum Error: Swift.Error { case malformed, incompatible, unauthorizedClaim }
    struct Health: Codable, Equatable {
        let protocolVersion: Int
        let release: String
        let signedPeerRequired: Bool
        let daemonHasRootPrivileges: Bool
        let rawDiskGrantsEnabled: Bool
        let availableOperations: [String]
    }
    static func health(isRoot: Bool) -> Health {
        Health(protocolVersion: protocolVersion, release: releaseVersion,
               signedPeerRequired: true, daemonHasRootPrivileges: isRoot,
               rawDiskGrantsEnabled: isRoot,
               availableOperations: ["healthReport", "readOnlyGrantStatus", "readOnlyTopology", "requestReadOnlyDisk", "releaseReadOnlyDisk"])
    }
    static func encode(_ report: Health) -> String {
        guard let payload = try? JSONEncoder().encode(report), payload.count <= maxPayloadBytes,
              let string = String(data: payload, encoding: .utf8) else { return "{}" }
        return string
    }
    static func decode(_ response: String) throws -> Health {
        guard response.utf8.count <= maxPayloadBytes,
              let bytes = response.data(using: .utf8),
              let result = try? JSONDecoder().decode(Health.self, from: bytes) else { throw Error.malformed }
        guard result.protocolVersion == protocolVersion else { throw Error.incompatible }
        guard result.signedPeerRequired,
              result.availableOperations.contains("readOnlyTopology"),
              !result.availableOperations.contains("openWritable"),
              !result.availableOperations.contains("openArbitraryPath"),
              (!result.rawDiskGrantsEnabled || (result.daemonHasRootPrivileges &&
                result.availableOperations.contains("requestReadOnlyDisk") &&
                result.availableOperations.contains("releaseReadOnlyDisk")))
        else { throw Error.unauthorizedClaim }
        return result
    }
    struct GrantedDisk: Codable, Equatable {
        let leaseID: String
        let bsdName: String
        let sizeBytes: UInt64
        let ioRegistryID: UInt64
    }
    static func encodeGrant(_ grant: GrantedDisk) -> String? {
        guard let data = try? JSONEncoder().encode(grant), data.count <= maxPayloadBytes else { return nil }
        return String(data: data, encoding: .utf8)
    }
    static func decodeGrant(_ payload: String, expectedBSD: String) throws -> GrantedDisk {
        guard payload.utf8.count <= maxPayloadBytes, let data = payload.data(using: .utf8),
              let result = try? JSONDecoder().decode(GrantedDisk.self, from: data),
              let _ = UUID(uuidString: result.leaseID),
              validWholeDisk(result.bsdName), result.bsdName == expectedBSD,
              result.sizeBytes > 0, result.ioRegistryID > 0 else { throw Error.malformed }
        return result
    }
    static func validWholeDisk(_ name: String) -> Bool {
        BrokerAuthorizationPolicy.isValidBSDName(name)
    }
}

/// Pure, auditable code requirement construction. Never accept an arbitrary signing
/// requirement, arbitrary team ID, or bundle ID from an XPC request.
enum BrokerSigningRequirements {
    static func validTeamID(_ team: String) -> Bool {
        team.count == 10 && team.utf8.allSatisfy { byte in
            (byte >= 48 && byte <= 57) || (byte >= 65 && byte <= 90)
        }
    }
    static func requirement(teamID: String, bundleID: String) -> String? {
        guard validTeamID(teamID),
              [DaemonBrokerContract.mainAppBundleID, DaemonBrokerContract.machService].contains(bundleID)
        else { return nil }
        return "identifier \"\(bundleID)\" and anchor apple generic and certificate leaf[subject.OU] = \"\(teamID)\""
    }
}
