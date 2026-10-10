import Foundation

/// This is an application XPC diagnostic endpoint, NOT an authority to open physical media.
@objc protocol DiskBrokerClientProtocol {
    func capabilityReport(withReply reply: @escaping (String) -> Void)
    func preflightSummary(_ bsdName: String, withReply reply: @escaping (String) -> Void)
    func leaseStatus(withReply reply: @escaping (String) -> Void)
}

@MainActor
final class DiskBrokerClient {
    enum ClientError: LocalizedError {
        case unavailable, interrupted, timeout
        var errorDescription: String? {
            switch self {
            case .unavailable: return "Disk broker XPC endpoint unavailable"
            case .interrupted: return "Disk broker XPC request interrupted"
            case .timeout: return "Disk broker XPC diagnostic timed out"
            }
        }
    }
    private let name = "ca.zensoftware.VolumeBoot.DiskBroker"

    func diagnostic() async throws -> String {
        // A service may accept the connection and never reply. The timeout task
        // must complete the continuation exactly once and invalidate the channel.
        let connection = NSXPCConnection(serviceName: name)
        connection.remoteObjectInterface = NSXPCInterface(with: DiskBrokerClientProtocol.self)
        let pending = PendingBrokerReply()
        connection.interruptionHandler = { pending.finish(.failure(ClientError.interrupted)) }
        connection.invalidationHandler = { pending.finish(.failure(ClientError.interrupted)) }
        connection.resume()
        defer { connection.invalidate() }
        let timeout = Task.detached {
            try? await Task.sleep(nanoseconds: BrokerProtocolContract.requestTimeoutNanoseconds)
            pending.finish(.failure(ClientError.timeout))
        }
        defer { timeout.cancel() }
        let payload = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            pending.install(continuation)
            guard let remote = connection.remoteObjectProxyWithErrorHandler({ _ in
                pending.finish(.failure(ClientError.unavailable))
            }) as? DiskBrokerClientProtocol else {
                pending.finish(.failure(ClientError.unavailable))
                return
            }
            remote.capabilityReport { pending.finish(.success($0)) }
        }
        let report = try BrokerProtocolContract.decode(payload)
        return "Disk broker v\(report.serviceVersion): diagnostics only; privileged=\(report.privileged); raw disk access=\(report.rawDiskAccessEnabled)"
    }
}

/// Lock-based single-completion gate for callback-based XPC and timeout races.
final class PendingBrokerReply: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<String, Error>?
    private var result: Result<String, Error>?
    func install(_ value: CheckedContinuation<String, Error>) {
        lock.lock()
        if let result { lock.unlock(); value.resume(with: result); return }
        continuation = value
        lock.unlock()
    }
    func finish(_ incoming: Result<String, Error>) {
        lock.lock()
        guard result == nil else { lock.unlock(); return }
        result = incoming
        let callback = continuation
        continuation = nil
        lock.unlock()
        callback?.resume(with: incoming)
    }
}
