import Foundation

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { fatalError("FAIL: " + message) }
}
let safe = PhysicalDiskSafetySnapshot(requestedBSD: "disk7", wholeBSD: "disk7", isWholeDisk: true,
    isInternal: false, isVirtual: false, isHostRootStore: false, hasMountedDescendant: false,
    hasAPFSPhysicalStore: false, hasStableIdentity: true, expectedIdentityMatches: true)
expect(PhysicalDiskSafetyPolicy.evaluate(safe) == .advisoryCandidate, "known-safe candidate")
let cases: [(String, (inout PhysicalDiskSafetySnapshotFields) -> Void)] = [
    ("internal", { $0.isInternal = true }),
    ("unknown internal", { $0.isInternal = nil }),
    ("mounted", { $0.hasMountedDescendant = true }),
    ("unknown mounts", { $0.hasMountedDescendant = nil }),
    ("APFS", { $0.hasAPFSPhysicalStore = true }),
    ("unknown APFS", { $0.hasAPFSPhysicalStore = nil }),
    ("host root", { $0.isHostRootStore = true }),
    ("unknown root", { $0.isHostRootStore = nil }),
    ("identity mismatch", { $0.expectedIdentityMatches = false }),
    ("virtual", { $0.isVirtual = true }),
    ("unknown virtual", { $0.isVirtual = nil }),
    ("wrong name", { $0.requestedBSD = "../../dev/disk7" }),
    ("partition", { $0.requestedBSD = "disk7s2" }),
    ("different parent", { $0.wholeBSD = "disk8" }),
]
struct PhysicalDiskSafetySnapshotFields {
    var requestedBSD = "disk7", wholeBSD = "disk7", isWholeDisk = true
    var isInternal: Bool? = false, isVirtual: Bool? = false, isHostRootStore: Bool? = false
    var hasMountedDescendant: Bool? = false, hasAPFSPhysicalStore: Bool? = false
    var hasStableIdentity = true, expectedIdentityMatches = true
    var snapshot: PhysicalDiskSafetySnapshot {
        PhysicalDiskSafetySnapshot(requestedBSD: requestedBSD, wholeBSD: wholeBSD,
            isWholeDisk: isWholeDisk, isInternal: isInternal, isVirtual: isVirtual,
            isHostRootStore: isHostRootStore, hasMountedDescendant: hasMountedDescendant,
            hasAPFSPhysicalStore: hasAPFSPhysicalStore, hasStableIdentity: hasStableIdentity,
            expectedIdentityMatches: expectedIdentityMatches)
    }
}
for (name, mutation) in cases {
    var c = PhysicalDiskSafetySnapshotFields(); mutation(&c)
    if case .denied = PhysicalDiskSafetyPolicy.evaluate(c.snapshot) {} else { fatalError("FAIL: " + name) }
}
var lease = DiskLeaseStateMachine()
let a = UUID(), b = UUID()
try lease.reserve(a)
do { try lease.reserve(b); fatalError("conflicting reservation allowed") }
catch DiskLeaseStateMachine.TransitionError.conflictingLease {}
try lease.attach(a)
do { try lease.release(b); fatalError("invalid release allowed") }
catch DiskLeaseStateMachine.TransitionError.invalidTransition {}
try lease.release(a)
expect(lease.state == .idle, "lease returns to idle")
lease.failClosed()
do { try lease.reserve(a); fatalError("failed lease reused") }
catch DiskLeaseStateMachine.TransitionError.conflictingLease {}
try lease.resetAfterRevalidation()
print("PASS: 1 advisory positive, \(cases.count) safety denials, 5 lease checks")
