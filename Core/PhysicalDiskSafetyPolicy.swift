import Foundation

/// Deterministic and testable part of the read-only physical media gate.
/// The privileged service MUST independently obtain all fields immediately before open.
struct PhysicalDiskSafetySnapshot: Sendable, Equatable {
    let requestedBSD: String
    let wholeBSD: String
    let isWholeDisk: Bool
    let isInternal: Bool?
    let isVirtual: Bool?
    let isHostRootStore: Bool?
    let hasMountedDescendant: Bool?
    let hasAPFSPhysicalStore: Bool?
    let hasStableIdentity: Bool
    let expectedIdentityMatches: Bool
}

enum PhysicalDiskSafetyDecision: Equatable {
    case denied([String])
    case advisoryCandidate
}

enum PhysicalDiskSafetyPolicy {
    static func validBSDName(_ name: String) -> Bool {
        name.range(of: #"^disk[0-9]+$"#, options: .regularExpression) != nil
    }

    static func evaluate(_ snapshot: PhysicalDiskSafetySnapshot) -> PhysicalDiskSafetyDecision {
        var failures: [String] = []
        if !validBSDName(snapshot.requestedBSD) || !validBSDName(snapshot.wholeBSD) { failures.append("Invalid whole-disk identifier") }
        if snapshot.requestedBSD != snapshot.wholeBSD || !snapshot.isWholeDisk { failures.append("Only entire physical disks are eligible") }
        if snapshot.isInternal != false { failures.append("Internal or unknown media denied") }
        if snapshot.isVirtual != false { failures.append("Virtual or unknown media denied") }
        if snapshot.isHostRootStore != false { failures.append("Host root store ownership is unknown or protected") }
        if snapshot.hasMountedDescendant != false { failures.append("Mounted descendant or unresolved mount state") }
        if snapshot.hasAPFSPhysicalStore != false { failures.append("APFS physical store requires specialized ownership analysis") }
        if !snapshot.hasStableIdentity || !snapshot.expectedIdentityMatches { failures.append("Identity unavailable or changed") }
        return failures.isEmpty ? .advisoryCandidate : .denied(failures)
    }
}
