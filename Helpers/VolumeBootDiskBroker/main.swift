import Foundation

// XPC transport only. This application-scoped service is NOT a privileged helper.
// The service grants no raw disk file descriptors, including when the caller
// has administrator privileges. Privileged provisioning requires an audited
// SMAppService daemon with audit-token-based caller validation.
@objc protocol DiskBrokerXPCProtocol {
    func capabilityReport(withReply reply: @escaping (String) -> Void)
    func preflightSummary(_ bsdName: String, withReply reply: @escaping (String) -> Void)
    func leaseStatus(withReply reply: @escaping (String) -> Void)
}

private enum BrokerBoundary {
    static let report = "VolumeBoot 0.12.0: diagnostic service only; physical access unavailable."
}

final class DiskBrokerService: NSObject, DiskBrokerXPCProtocol {
    func capabilityReport(withReply reply: @escaping (String) -> Void) {
        reply(BrokerProtocolContract.encode(BrokerProtocolContract.report()))
    }
    func preflightSummary(_ bsdName: String, withReply reply: @escaping (String) -> Void) {
        guard BrokerAuthorizationPolicy.decide(.preflight, bsdName: bsdName) == .allowDiagnostic else {
            reply("REJECTED: invalid BSD device name")
            return
        }
        reply("\(bsdName): inspection is advisory; no physical disk access granted")
    }
    func leaseStatus(withReply reply: @escaping (String) -> Void) {
        reply("0 active physical disk leases; issuance disabled")
    }
}

final class BrokerListener: NSObject, NSXPCListenerDelegate {
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        // Only non-sensitive diagnostics may be invoked through this endpoint.
        // No privileged operations or descriptor transfer are exposed.
        connection.exportedInterface = NSXPCInterface(with: DiskBrokerXPCProtocol.self)
        connection.exportedObject = DiskBrokerService()
        connection.resume()
        return true
    }
}

let delegate = BrokerListener()
let listener = NSXPCListener.service()
listener.delegate = delegate
listener.resume()
RunLoop.current.run()
