import Foundation

@main enum ReadOnlyGrantPolicyTests {
    static func main() {
        var passed = 0
        func check(_ yes: Bool, _ why: String) {
            precondition(yes, why)
            passed += 1
        }
        let good = ReadOnlyGrantSnapshot(requestedBSD: "disk9", reportedBSD: "disk9",
            wholeDisk: true, internalMedia: false, physicalMedia: true,
            externalLocation: true, mounted: false, partitionCount: 0, anyAPFS: false,
            hasFilesystem: false, sizeBytes: 64_000_000, mediaRegistryID: 456)
        check(ReadOnlyGrantPolicy.allowed(good), "blank external test disk")
        func negative(_ updated: (ReadOnlyGrantSnapshot) -> ReadOnlyGrantSnapshot, _ why: String) {
            check(!ReadOnlyGrantPolicy.allowed(updated(good)), why)
        }
        func altered(_ bsd: String = "disk9", _ reported: String = "disk9", _ whole: Bool? = true,
                     _ internalMedia: Bool? = false, _ physical: Bool? = true, _ external: Bool? = true,
                     _ mounted: Bool? = false, _ partitions: Int? = 0, _ apfs: Bool? = false,
                     _ filesystem: Bool? = false, _ size: UInt64? = 64_000_000,
                     _ registry: UInt64? = 456) -> ReadOnlyGrantSnapshot {
            ReadOnlyGrantSnapshot(requestedBSD: bsd, reportedBSD: reported, wholeDisk: whole,
              internalMedia: internalMedia, physicalMedia: physical, externalLocation: external,
              mounted: mounted, partitionCount: partitions, anyAPFS: apfs,
              hasFilesystem: filesystem, sizeBytes: size, mediaRegistryID: registry)
        }
        negative({ _ in altered("disk9s1") }, "partition request")
        negative({ _ in altered("../dev/disk1") }, "path injection")
        negative({ _ in altered("disk9", "disk8") }, "renumbered disk")
        negative({ _ in altered("disk9", "disk9", nil) }, "missing whole state")
        negative({ _ in altered("disk9", "disk9", false) }, "not whole")
        negative({ _ in altered("disk9", "disk9", true, nil) }, "unknown internal")
        negative({ _ in altered("disk9", "disk9", true, true) }, "internal")
        negative({ _ in altered("disk9", "disk9", true, false, nil) }, "unknown physical")
        negative({ _ in altered("disk9", "disk9", true, false, false) }, "virtual")
        negative({ _ in altered("disk9", "disk9", true, false, true, nil) }, "unknown location")
        negative({ _ in altered("disk9", "disk9", true, false, true, false) }, "not external")
        negative({ _ in altered("disk9", "disk9", true, false, true, true, nil) }, "unknown mount")
        negative({ _ in altered("disk9", "disk9", true, false, true, true, true) }, "mounted")
        negative({ _ in altered("disk9", "disk9", true, false, true, true, false, nil) }, "unknown partitions")
        negative({ _ in altered("disk9", "disk9", true, false, true, true, false, 1) }, "has partitions")
        negative({ _ in altered("disk9", "disk9", true, false, true, true, false, 0, nil) }, "unknown APFS")
        negative({ _ in altered("disk9", "disk9", true, false, true, true, false, 0, true) }, "APFS")
        negative({ _ in altered("disk9", "disk9", true, false, true, true, false, 0, false, nil) }, "unknown filesystem")
        negative({ _ in altered("disk9", "disk9", true, false, true, true, false, 0, false, true) }, "existing filesystem")
        negative({ _ in altered("disk9", "disk9", true, false, true, true, false, 0, false, false, nil) }, "unknown size")
        negative({ _ in altered("disk9", "disk9", true, false, true, true, false, 0, false, false, 0) }, "zero size")
        negative({ _ in altered("disk9", "disk9", true, false, true, true, false, 0, false, false, 64000000, nil) }, "unknown registry")
        negative({ _ in altered("disk9", "disk9", true, false, true, true, false, 0, false, false, 64000000, 0) }, "zero registry")
        let reservations = DiskGrantReservations()
        let a = UUID(), b = UUID()
        check(reservations.reserve("disk9", for: a), "first reservation")
        check(!reservations.reserve("disk9", for: b), "no double lease")
        reservations.release("disk9", for: b)
        check(reservations.isReserved("disk9"), "foreign release denied")
        reservations.release("disk9", for: a)
        check(!reservations.isReserved("disk9"), "correct release")
        check(reservations.reserve("disk9", for: b), "reuse after release")
        print("Read-only physical disk grant policy PASS: \(passed) checks")
    }
}
