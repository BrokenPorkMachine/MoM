import Foundation

/// Protocol-only placeholder. No privileged service is installed by this scaffold.
/// Never turn a BSD device name from the UI into an unrestricted open() call.
struct DiskLeaseRequest: Codable, Sendable {
    let stableDeviceID: String
    let readOnly: Bool
    let expectedWholeDiskIdentity: String
}

enum DiskBrokerPolicy {
    static func allowRequest(_ request: DiskLeaseRequest) -> Bool {
        // Fail closed until code signing, topology traversal, lease ownership and XPC FD transfer exist.
        false
    }
}
