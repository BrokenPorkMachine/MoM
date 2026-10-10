import Foundation
import ServiceManagement
import Security

/// Never silently installs a root service. Registration is a separate explicit user action.
@MainActor
final class PrivilegedBrokerClient {
    enum ClientFailure: LocalizedError {
        case notSigned, invalidSigner, unavailable, interrupted, timeout
        var errorDescription: String? {
            switch self {
            case .notSigned: return "A valid Apple Developer signing identity is needed before installing this daemon"
            case .invalidSigner: return "Could not establish a trusted, matching code-signing requirement"
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
        return "Signed daemon v\(health.release) connected; root=yes; blank-media disk grants=\(health.rawDiskGrantsEnabled ? "ENABLED" : "DISABLED")"
    }

    /// Returns a read-only topology report. This is not an authorization or a
    /// claim and must never trigger raw-device attachment.
    func inspectTopology(_ name: String) async throws -> String {
        guard DaemonBrokerContract.validWholeDisk(name) else { throw PhysicalDiskError.invalidBSDName }
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

/// Owns the XPC connection for as long as a guest might access the disk.
/// Caller MUST stop the guest before releasing. Closing the daemon copy alone
/// does not revoke an already transferred capability on the client side.
@MainActor
final class PrivilegedDiskGrant {
    let disk: ReadOnlyPhysicalDiskLease
    let metadata: DaemonBrokerContract.GrantedDisk
    private let connection: NSXPCConnection
    private var released = false

    init(disk: ReadOnlyPhysicalDiskLease, metadata: DaemonBrokerContract.GrantedDisk,
         connection: NSXPCConnection) {
        self.disk = disk
        self.metadata = metadata
        self.connection = connection
    }

    func releaseAfterVMStops() {
        guard !released else { return }
        released = true
        try? disk.close()
        if let service = connection.remoteObjectProxyWithErrorHandler({ _ in }) as? VolumeBootPrivilegedDaemonProtocol {
            service.releaseReadOnlyDisk(metadata.leaseID) { _ in }
        }
        connection.invalidate()
    }
}

/// Completes at most once even when the XPC reply, timeout, or invalidation race.
private final class PendingPhysicalGrant {
    typealias Response = (FileHandle?, String, String)
    private let lock = NSLock()
    private var result: Result<Response, Error>?
    private var continuation: CheckedContinuation<Response, Error>?

    func install(_ continuation: CheckedContinuation<Response, Error>) {
        lock.lock()
        if let result = result {
            lock.unlock()
            continuation.resume(with: result)
        } else {
            self.continuation = continuation
            lock.unlock()
        }
    }
    func finish(_ result: Result<Response, Error>) {
        lock.lock()
        guard self.result == nil else { lock.unlock(); return }
        self.result = result
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(with: result)
    }
}

extension PrivilegedBrokerClient {
    /// Uses only a signed root daemon and grants only strictly validated
    /// unpartitioned/unmounted external test media. Never opens /dev in the GUI.
    func acquireDisposableExternalDisk(_ name: String) async throws -> PrivilegedDiskGrant {
        guard BrokerAuthorizationPolicy.isValidBSDName(name) else { throw PhysicalDiskError.invalidBSDName }
        guard let team = try signedTeamID(),
              let requirement = BrokerSigningRequirements.requirement(teamID: team,
                  bundleID: DaemonBrokerContract.machService) else { throw ClientFailure.notSigned }
        let connection = NSXPCConnection(machServiceName: DaemonBrokerContract.machService,
                                         options: [.privileged])
        connection.remoteObjectInterface = NSXPCInterface(with: VolumeBootPrivilegedDaemonProtocol.self)
        connection.setCodeSigningRequirement(requirement)
        let pending = PendingPhysicalGrant()
        connection.interruptionHandler = { pending.finish(.failure(ClientFailure.interrupted)) }
        connection.invalidationHandler = { pending.finish(.failure(ClientFailure.interrupted)) }
        connection.resume()
        let timer = Task.detached {
            do { try await Task.sleep(nanoseconds: BrokerProtocolContract.requestTimeoutNanoseconds) }
            catch { return }
            pending.finish(.failure(ClientFailure.timeout))
        }
        do {
            let (handle, payload, reason) = try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<PendingPhysicalGrant.Response, Error>) in
                pending.install(continuation)
                guard let service = connection.remoteObjectProxyWithErrorHandler({ _ in
                    pending.finish(.failure(ClientFailure.unavailable))
                }) as? VolumeBootPrivilegedDaemonProtocol else {
                    pending.finish(.failure(ClientFailure.unavailable)); return
                }
                service.requestReadOnlyDisk(name) { fd, grant, message in
                    pending.finish(.success((fd, grant, message)))
                }
            }
            timer.cancel()
            guard let handle else { throw PhysicalDiskError.permissionDeniedWithReason(reason) }
            defer { try? handle.close() }
            let metadata = try DaemonBrokerContract.decodeGrant(payload, expectedBSD: name)
            let identity = PhysicalDiskIdentity(bsdName: name, wholeDiskBSDName: name,
                mediaUUID: "IORegistry:\(metadata.ioRegistryID)", sizeBytes: metadata.sizeBytes,
                isInternal: false, isWholeDisk: true)
            let lease = try ReadOnlyPhysicalDiskLease(identity: identity,
                sessionID: UUID(uuidString: metadata.leaseID)!,
                transferredDescriptor: handle.fileDescriptor)
            return PrivilegedDiskGrant(disk: lease, metadata: metadata, connection: connection)
        } catch {
            timer.cancel()
            connection.invalidate()
            throw error
        }
    }
}
