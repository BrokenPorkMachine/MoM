import Foundation
import Security
import Darwin

/// Each incoming authenticated XPC connection gets its own service instance.
/// Handles retained in the daemon close on connection invalidation. Closing
/// the daemon copy does NOT revoke a previously transferred client descriptor.
final class VolumeBootRawDiskDaemon: NSObject, VolumeBootPrivilegedDaemonProtocol {
    private let reservations: DiskGrantReservations
    private let workQueue = DispatchQueue(label: "ca.zensoftware.VolumeBoot.disk-grant", qos: .utility)
    private let lock = NSLock()
    private var active: (name: String, id: UUID, handle: FileHandle)?
    private var terminated = false

    init(reservations: DiskGrantReservations) { self.reservations = reservations }

    func healthReport(withReply reply: @escaping (String) -> Void) {
        reply(DaemonBrokerContract.encode(DaemonBrokerContract.health(isRoot: geteuid() == 0)))
    }

    func readOnlyGrantStatus(_ wholeDiskBSDName: String, withReply reply: @escaping (String) -> Void) {
        guard DaemonBrokerContract.validWholeDisk(wholeDiskBSDName) else {
            reply("DENIED: invalid identifier"); return
        }
        reply("RESTRICTED: only unpartitioned, unmounted external test disks; explicit user approval required")
    }

    func readOnlyTopology(_ wholeDiskBSDName: String, withReply reply: @escaping (String) -> Void) {
        guard DaemonBrokerContract.validWholeDisk(wholeDiskBSDName) else {
            reply("DENIED: invalid whole-disk identifier"); return
        }
        workQueue.async {
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

    func requestReadOnlyDisk(_ wholeDiskBSDName: String,
                             withReply reply: @escaping (FileHandle?, String, String) -> Void) {
        guard DaemonBrokerContract.validWholeDisk(wholeDiskBSDName) else {
            reply(nil, "", "Invalid whole disk identifier"); return
        }
        // Never execute diskutil or open a /dev node on the XPC dispatch thread.
        workQueue.async { [self] in
            lock.lock()
            let busy = terminated || active != nil
            lock.unlock()
            guard !busy, geteuid() == 0 else {
                reply(nil, "", "Connection already leased, invalidated, or not privileged"); return
            }
            let token = UUID()
            guard reservations.reserve(wholeDiskBSDName, for: token) else {
                reply(nil, "", "Disk already reserved by another connection"); return
            }
            var keepReservation = false
            defer { if !keepReservation { reservations.release(wholeDiskBSDName, for: token) } }
            do {
                let handle = try TrustedDiskProbe.openVerifiedReadOnly(wholeDiskBSDName)
                let snapshot = try TrustedDiskProbe.snapshot(wholeDiskBSDName)
                guard ReadOnlyGrantPolicy.allowed(snapshot), let registry = snapshot.mediaRegistryID,
                      let size = snapshot.sizeBytes else {
                    try? handle.close()
                    reply(nil, "", "Final device identity verification failed"); return
                }
                let grant = DaemonBrokerContract.GrantedDisk(leaseID: token.uuidString,
                    bsdName: wholeDiskBSDName, sizeBytes: size, ioRegistryID: registry)
                guard let payload = DaemonBrokerContract.encodeGrant(grant) else {
                    try? handle.close()
                    reply(nil, "", "Grant metadata encoding failed"); return
                }
                lock.lock()
                if terminated || active != nil {
                    lock.unlock()
                    try? handle.close()
                    reply(nil, "", "Connection invalidated while inspecting media"); return
                }
                active = (wholeDiskBSDName, token, handle)
                keepReservation = true
                lock.unlock()
                reply(handle, payload, "")
            } catch {
                reply(nil, "", "Read-only grant rejected: \(error.localizedDescription)")
            }
        }
    }

    func releaseReadOnlyDisk(_ leaseID: String, withReply reply: @escaping (Bool) -> Void) {
        guard let token = UUID(uuidString: leaseID) else { reply(false); return }
        lock.lock()
        let item = active
        if item?.id == token { active = nil }
        lock.unlock()
        guard let item, item.id == token else { reply(false); return }
        reservations.release(item.name, for: item.id)
        try? item.handle.close()
        reply(true)
    }

    func invalidate() {
        lock.lock()
        terminated = true
        let item = active
        active = nil
        lock.unlock()
        if let item {
            reservations.release(item.name, for: item.id)
            try? item.handle.close()
        }
    }
}

final class SignedBrokerListener: NSObject, NSXPCListenerDelegate {
    private let reservations = DiskGrantReservations()
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        // Enforcement is performed by NSXPCListener's signing requirement;
        // no caller-provided identity, PID, or pathname is trusted.
        let service = VolumeBootRawDiskDaemon(reservations: reservations)
        connection.exportedInterface = NSXPCInterface(with: VolumeBootPrivilegedDaemonProtocol.self)
        connection.exportedObject = service
        connection.invalidationHandler = { service.invalidate() }
        connection.interruptionHandler = { service.invalidate() }
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
