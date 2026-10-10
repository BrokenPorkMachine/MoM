import Foundation

/// Shared, pure policy. It is NOT a substitute for OS code-signing/audit-token checks.
enum BrokerAuthorizationPolicy {
    enum Operation: String, Codable { case capability, preflight, leaseStatus, openReadOnly, openWritable }
    enum Decision: Equatable {
        case allowDiagnostic
        case deny(String)
    }
    static func isValidBSDName(_ name: String) -> Bool {
        // Only whole disk identifiers accepted at the XPC boundary.
        guard name.utf8.count <= 32 else { return false }
        guard name.hasPrefix("disk") else { return false }
        let digits = name.dropFirst(4)
        guard !digits.isEmpty, digits.count <= 10, digits.allSatisfy({ $0 >= "0" && $0 <= "9" }) else { return false }
        return digits.count == 1 || digits.first != "0"
    }
    static func decide(_ operation: Operation, bsdName: String? = nil) -> Decision {
        switch operation {
        case .capability, .leaseStatus: return .allowDiagnostic
        case .preflight:
            guard let bsdName, isValidBSDName(bsdName) else { return .deny("invalid whole-disk identifier") }
            return .allowDiagnostic
        case .openReadOnly:
            return .deny("privileged signed helper and device ownership checks not yet installed")
        case .openWritable:
            return .deny("writable physical-disk access disabled by policy")
        }
    }
}
