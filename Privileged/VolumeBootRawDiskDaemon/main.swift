import Foundation
import Security
import Darwin

/// Production service exposes metadata inspection only. Physical disk grant
/// methods and raw-device opening code are excluded from this target.
final class VolumeBootRawDiskDaemon: NSObject, VolumeBootPrivilegedDaemonProtocol {
    func healthReport(withReply reply: @escaping (String) -> Void) {
        reply(DaemonBrokerContract.encode(DaemonBrokerContract.health(isRoot: geteuid() == 0)))
    }

    func readOnlyGrantStatus(_ wholeDiskBSDName: String, withReply reply: @escaping (String) -> Void) {
        guard DaemonBrokerContract.validWholeDisk(wholeDiskBSDName) else {
            reply("DENIED: invalid identifier"); return
        }
        reply("DISABLED: this service has no physical disk attachment or descriptor-grant operation; topology inspection is read-only")
    }

    func readOnlyTopology(_ wholeDiskBSDName: String, withReply reply: @escaping (String) -> Void) {
        guard DaemonBrokerContract.validWholeDisk(wholeDiskBSDName) else {
            reply("DENIED: invalid whole-disk identifier"); return
        }
        DispatchQueue.global(qos: .utility).async {
            do {
                let report = try PhysicalDiskTopologyProbe.inspect(wholeDiskBSDName)
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.sortedKeys]
                let encoded = try encoder.encode(report)
                guard encoded.count <= 32_768, let text = String(data: encoded, encoding: .utf8) else {
                    reply("INCONCLUSIVE: diagnostics exceeded size limit"); return
                }
                reply(text)
            } catch {
                reply("INCONCLUSIVE: \(error.localizedDescription)")
            }
        }
    }

}

final class SignedBrokerListener: NSObject, NSXPCListenerDelegate {
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        // Enforcement is performed by NSXPCListener's signing requirement;
        // no caller-provided identity, PID, or pathname is trusted.
        let service = VolumeBootRawDiskDaemon()
        connection.exportedInterface = NSXPCInterface(with: VolumeBootPrivilegedDaemonProtocol.self)
        connection.exportedObject = service
        connection.resume()
        return true
    }
}

func trustedSelfTeamID() -> String? {
    var code: SecCode?
    guard SecCodeCopySelf(SecCSFlags(rawValue: 0), &code) == errSecSuccess, let code else { return nil }
    guard SecCodeCheckValidity(code, SecCSFlags(rawValue: 0), nil) == errSecSuccess else { return nil }
    var staticCode: SecStaticCode?
    guard SecCodeCopyStaticCode(code, SecCSFlags(rawValue: 0), &staticCode) == errSecSuccess,
          let staticCode else { return nil }
    var details: CFDictionary?
    guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &details) == errSecSuccess,
          let dict = details as? [String: Any],
          let team = dict[kSecCodeInfoTeamIdentifier as String] as? String,
          BrokerSigningRequirements.validTeamID(team) else { return nil }
    return team
}

guard geteuid() == 0,
      let team = trustedSelfTeamID(),
      let requirement = BrokerSigningRequirements.requirement(teamID: team,
                    bundleID: DaemonBrokerContract.mainAppBundleID) else {
    fputs("VolumeBootRawDiskDaemon: trusted root signing required\n", stderr)
    exit(78)
}
let daemonDelegate = SignedBrokerListener()
let daemonListener = NSXPCListener(machServiceName: DaemonBrokerContract.machService)
daemonListener.setConnectionCodeSigningRequirement(requirement)
daemonListener.delegate = daemonDelegate
daemonListener.resume()
RunLoop.current.run()
