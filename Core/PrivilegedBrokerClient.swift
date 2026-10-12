import Foundation
import ServiceManagement
import Security

/// Never silently installs a root service. Registration is a separate explicit user action.
@MainActor
final class PrivilegedBrokerClient {
    enum ClientFailure: LocalizedError {
        case notSigned, invalidSigner, invalidDiskIdentifier, unavailable, interrupted, timeout
        var errorDescription: String? {
            switch self {
            case .notSigned: return "A valid Apple Developer signing identity is needed before installing this daemon"
            case .invalidSigner: return "Could not establish a trusted, matching code-signing requirement"
            case .invalidDiskIdentifier: return "Invalid whole-disk identifier"
            case .unavailable: return "Privileged service connection is unavailable or not approved"
            case .interrupted: return "Privileged broker disconnected"
            case .timeout: return "Privileged broker timed out"
            }
        }
    }
    private var service: SMAppService { .daemon(plistName: DaemonBrokerContract.daemonPlist) }

    func currentStatus() -> String {
        switch service.status {
        case .enabled: return "Approved and registered (daemon runtime not yet verified)"
        case .requiresApproval: return "Requires approval in System Settings → General → Login Items & Extensions"
        case .notRegistered: return "Not registered"
        case .notFound: return "Daemon not found in application bundle"
        @unknown default: return "Unknown service registration state"
        }
    }

    func registerWithUserApproval() throws -> String {
        guard try signedTeamID() != nil else { throw ClientFailure.notSigned }
        try service.register()
        return currentStatus()
    }

    func openApprovalSettings() { SMAppService.openSystemSettingsLoginItems() }

    func checkHealth() async throws -> String {
        guard let team = try signedTeamID() else { throw ClientFailure.notSigned }
        guard let requirement = BrokerSigningRequirements.requirement(teamID: team,
                                 bundleID: DaemonBrokerContract.machService) else { throw ClientFailure.invalidSigner }
        let connection = NSXPCConnection(machServiceName: DaemonBrokerContract.machService,
                                         options: [.privileged])
        connection.remoteObjectInterface = NSXPCInterface(with: VolumeBootPrivilegedDaemonProtocol.self)
        connection.setCodeSigningRequirement(requirement)
        let pending = PendingBrokerReply()
        connection.interruptionHandler = { pending.finish(.failure(ClientFailure.interrupted)) }
        connection.invalidationHandler = { pending.finish(.failure(ClientFailure.interrupted)) }
        connection.resume()
        defer { connection.invalidate() }
        let timeout = Task.detached {
            do { try await Task.sleep(nanoseconds: BrokerProtocolContract.requestTimeoutNanoseconds) }
            catch { return }
            pending.finish(.failure(ClientFailure.timeout))
        }
        defer { timeout.cancel() }
        let response = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            pending.install(continuation)
            guard let remote = connection.remoteObjectProxyWithErrorHandler({ _ in
                pending.finish(.failure(ClientFailure.unavailable))
            }) as? VolumeBootPrivilegedDaemonProtocol else {
                pending.finish(.failure(ClientFailure.unavailable))
                return
            }
            remote.healthReport { pending.finish(.success($0)) }
        }
        let health = try DaemonBrokerContract.decode(response)
        guard health.daemonHasRootPrivileges else { throw ClientFailure.unavailable }
        return "Signed daemon v\(health.release) connected; root=yes; physical-disk grants=DISABLED"
    }

    /// Returns a read-only topology report. This is not an authorization or a
    /// claim and must never trigger raw-device attachment.
    func inspectTopology(_ name: String) async throws -> String {
        guard DaemonBrokerContract.validWholeDisk(name) else { throw ClientFailure.invalidDiskIdentifier }
        guard let team = try signedTeamID(),
              let requirement = BrokerSigningRequirements.requirement(teamID: team,
                    bundleID: DaemonBrokerContract.machService) else { throw ClientFailure.notSigned }
        let connection = NSXPCConnection(machServiceName: DaemonBrokerContract.machService,
                                         options: [.privileged])
        connection.remoteObjectInterface = NSXPCInterface(with: VolumeBootPrivilegedDaemonProtocol.self)
        connection.setCodeSigningRequirement(requirement)
        let pending = PendingBrokerReply()
        connection.interruptionHandler = { pending.finish(.failure(ClientFailure.interrupted)) }
        connection.invalidationHandler = { pending.finish(.failure(ClientFailure.interrupted)) }
        connection.resume()
        defer { connection.invalidate() }
        let timeout = Task.detached {
            do { try await Task.sleep(nanoseconds: BrokerProtocolContract.requestTimeoutNanoseconds) }
            catch { return }
            pending.finish(.failure(ClientFailure.timeout))
        }
        defer { timeout.cancel() }
        let response = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<String, Error>) in
            pending.install(cont)
            guard let service = connection.remoteObjectProxyWithErrorHandler({ _ in
                pending.finish(.failure(ClientFailure.unavailable))
            }) as? VolumeBootPrivilegedDaemonProtocol else {
                pending.finish(.failure(ClientFailure.unavailable)); return
            }
            service.readOnlyTopology(name) { pending.finish(.success($0)) }
        }
        if let data = response.data(using: .utf8),
           let report = try? JSONDecoder().decode(PhysicalDiskTopologyReport.self, from: data) {
            let impact = report.reasons.isEmpty ? "none" : report.reasons.joined(separator: "; ")
            let limitations = report.limitations.isEmpty ? "none" : report.limitations.joined(separator: "; ")
            return "Topology \(name): \(report.verdict.rawValue); APFS=\(report.hasAPFS); " +
                   "\(report.apfsContainers.count) containers, \(report.apfsVolumes.count) volumes; " +
                   "hostRoot=\(report.containsHostRoot.map(String.init(describing:)) ?? "unknown"); " +
                   "mounts=\(report.mountedDevices.joined(separator: ",")); " +
                   "denials=\(impact); limitations=\(limitations). " +
                   "ANALYSIS ONLY: no APFS grants and no exclusive claim."
        }
        return "Topology inspection unavailable: " + String(response.prefix(512))
    }

    /// Read only self-signature verification. Rejects unsigned/ad hoc binary.
    private func signedTeamID() throws -> String? {
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
}
