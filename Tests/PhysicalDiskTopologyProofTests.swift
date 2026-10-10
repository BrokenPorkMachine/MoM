import Foundation

@main enum PhysicalDiskTopologyProofTests {
    static var count = 0
    static func check(_ condition: @autoclosure () -> Bool, _ label: String) {
        precondition(condition(), label); count += 1
    }
    static func main() throws {
        func fixture(_ mounted: Bool = false) -> (list: [String:Any], apfs: [String:Any], info: [String:[String:Any]]) {
            let list: [String: Any] = ["AllDisksAndPartitions": [
                ["DeviceIdentifier":"disk9", "Content":"GUID_partition_scheme",
                 "Partitions":[["DeviceIdentifier":"disk9s1", "Content":"EFI"],
                               ["DeviceIdentifier":"disk9s2", "Content":"Apple_APFS"]]],
                ["DeviceIdentifier":"disk1", "Partitions":[["DeviceIdentifier":"disk1s1"]]]]]
            let apfs: [String: Any] = ["Containers":[
                ["ContainerReference":"disk12",
                 "PhysicalStores":[["DeviceIdentifier":"disk9s2"]],
                 "Volumes":[["DeviceIdentifier":"disk12s1", "Roles":["System"]],
                            ["DeviceIdentifier":"disk12s2", "Roles":["Data"]]]],
                ["ContainerReference":"disk3",
                 "PhysicalStores":[["DeviceIdentifier":"disk1s1"]],
                 "Volumes":[["DeviceIdentifier":"disk3s1", "Roles":["System"]]]]
            ]]
            let info: [String: [String: Any]] = [
                "disk9":["DeviceIdentifier":"disk9", "WholeDisk":true,"Internal":false,
                         "DeviceLocation":"External", "VirtualOrPhysical":"Physical",
                         "TotalSize":NSNumber(value: 2_000_000_000),"Mounted":false],
                "disk9s1":["DeviceIdentifier":"disk9s1","Mounted":false],
                "disk9s2":["DeviceIdentifier":"disk9s2","Mounted":false],
                "disk12s1":["DeviceIdentifier":"disk12s1","Mounted":mounted],
                "disk12s2":["DeviceIdentifier":"disk12s2","Mounted":false]
            ]
            return (list,apfs,info)
        }
        func run(_ f: (list:[String:Any],apfs:[String:Any],info:[String:[String:Any]]),
                 root: String? = "disk3s1") -> PhysicalDiskTopologyReport {
            PhysicalDiskTopologyProof.analyze(target:"disk9",diskList:f.list,apfsList:f.apfs,
                info:f.info,hostRootBSD:root)
        }
        let base = run(fixture())
        check(base.hasAPFS, "APFS detected on physical store")
        check(base.apfsContainers == ["disk12"], "target APFS only")
        check(base.apfsVolumes == ["disk12s1", "disk12s2"], "both synthesized volumes")
        check(base.descendants == ["disk9", "disk9s1", "disk9s2"], "descendant graph")
        check(base.containsHostRoot == false, "host root on separate disk")
        check(base.mountedDevices.isEmpty, "no mounted volumes")
        check(base.verdict == .inconclusive, "APFS candidate does NOT authorize a grant")
        check(base.limitations.contains(where: {$0.contains("inspection-only")}), "exclusive DA claim missing")
        let mounted = run(fixture(true))
        check(mounted.verdict == .denied, "mounted synthetic APFS volume blocked")
        check(mounted.mountedDevices == ["disk12s1"], "synthetic mount detected")
        check(run(fixture(),root:"disk12s1s1").containsHostRoot == true, "APFS root snapshot matches")
        check(run(fixture(),root:"disk12s1s1").verdict == .denied, "host-root disk denied")
        check(run(fixture(),root:nil).verdict == .inconclusive, "missing root not assumed safe")
        var other = fixture()
        var containers = other.apfs["Containers"] as! [[String:Any]]
        var first = containers[0]
        first["PhysicalStores"] = [["DeviceIdentifier":"disk9s2"],["DeviceIdentifier":"disk8s2"]]
        containers[0] = first; other.apfs["Containers"] = containers
        let multi = run(other)
        check(multi.verdict == .denied, "multi-store APFS denied")
        check(multi.reasons.contains(where: {$0.contains("spans another")}), "cross-disk store reason")
        other = fixture(); other.info.removeValue(forKey:"disk12s2")
        check(run(other).limitations.contains(where: {$0.contains("Missing or changed")}), "missing synthesized volume")
        other = fixture(); other.info["disk9s2"]?["DeviceIdentifier"] = "disk7s1"
        check(run(other).verdict == .inconclusive, "changed partition metadata")
        other = fixture(); other.info["disk9"]?["Internal"] = true
        check(run(other).verdict == .denied, "internal device denied")
        other = fixture(); other.info["disk9"]?["DeviceLocation"] = "Unknown"
        check(run(other).verdict == .denied, "unknown transport denied")
        check(PhysicalDiskTopologyProof.analyze(target:"/dev/disk9",diskList:fixture().list,
            apfsList:fixture().apfs,info:fixture().info,hostRootBSD:"disk3s1").verdict == .denied,
            "no paths accepted")
        check(PhysicalDiskTopologyProof.analyze(target:"disk9",diskList:fixture().list,
            apfsList:nil,info:fixture().info,hostRootBSD:"disk3s1").verdict == .inconclusive,
            "unavailable APFS map")
        other = fixture()
        var disks = other.list["AllDisksAndPartitions"] as! [[String:Any]]
        disks[0].removeValue(forKey: "Partitions")
        other.list["AllDisksAndPartitions"] = disks
        check(run(other).verdict == .inconclusive, "missing partition tree not considered empty")
        other = fixture(); var c = other.apfs["Containers"] as! [[String:Any]]
        c[0].removeValue(forKey: "PhysicalStores"); other.apfs["Containers"] = c
        check(run(other).verdict == .inconclusive, "missing physical store map denied")
        // A truly blank whole disk can be a metadata-only candidate, but that
        // verdict is never a kernel-backed exclusive lease.
        let blankList: [String:Any] = ["AllDisksAndPartitions":[["DeviceIdentifier":"disk9", "Content":"", "Partitions":[]]]]
        let blankInfo: [String:[String:Any]] = ["disk9":["DeviceIdentifier":"disk9", "WholeDisk":true,
            "Internal":false, "DeviceLocation":"External", "VirtualOrPhysical":"Physical",
            "TotalSize":NSNumber(value: 4_000_000), "Mounted":false]]
        let blank = PhysicalDiskTopologyProof.analyze(target:"disk9",diskList:blankList,
            apfsList:["Containers":[]],info:blankInfo,hostRootBSD:"disk3s1")
        check(blank.verdict == .candidateUnclaimed, "blank external media may be research candidate")
        check(blank.apfsContainers.isEmpty, "blank media not misclassified as APFS")
        var unknownMount = fixture()
        unknownMount.info["disk12s1"]?.removeValue(forKey:"Mounted")
        check(run(unknownMount).verdict == .inconclusive, "unknown synthesized mount denied")
        var inconsistentRoot = fixture()
        inconsistentRoot.info["disk9"]?["WholeDisk"] = false
        check(run(inconsistentRoot).verdict == .denied, "whole disk status must be proven")
        let data = try JSONEncoder().encode(base)
        let decoded = try JSONDecoder().decode(PhysicalDiskTopologyReport.self,from:data)
        check(decoded == base,
              "report JSON roundtrip")
        print("Physical disk topology proof PASS: \(count) checks")
    }
}
