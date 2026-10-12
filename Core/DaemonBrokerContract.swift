import Foundation

/// Public contract for the separately signed, inspection-only launchd daemon.
#if canImport(ObjectiveC)
@objc protocol VolumeBootPrivilegedDaemonProtocol {
    func healthReport(withReply reply: @escaping (String) -> Void)
    func readOnlyGrantStatus(_ wholeDiskBSDName: String, withReply reply: @escaping (String) -> Void)
    func readOnlyTopology(_ wholeDiskBSDName: String, withReply reply: @escaping (String) -> Void)
}
#endif

enum DaemonBrokerContract {
    static let protocolVersion = 3
    static let releaseVersion = "0.16.0"
    static let machService = "ca.zensoftware.MacOnMac.RawDiskBroker"
    static let daemonPlist = machService + ".plist"
    static let mainAppBundleID = "ca.zensoftware.MacOnMac"
    static let daemonExecutable = "VolumeBootRawDiskDaemon"
    static let maxPayloadBytes = 4_096
    /// Physical device handles are intentionally unavailable in the release build.
    static let rawDiskGrantsEnabled = false

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
               rawDiskGrantsEnabled: false,
               availableOperations: ["healthReport", "readOnlyGrantStatus", "readOnlyTopology"])
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
              !result.rawDiskGrantsEnabled,
              result.availableOperations.contains("readOnlyTopology"),
              !result.availableOperations.contains("openWritable"),
              !result.availableOperations.contains("openArbitraryPath")
        else { throw Error.unauthorizedClaim }
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
