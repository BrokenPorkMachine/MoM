import Foundation
import DiskArbitration

/// Daemon-only read-only evidence collector. A successful report is not a grant.
/// Source of truth is freshly obtained system metadata; never caller-supplied maps.
enum PhysicalDiskTopologyProbe {
    enum ProbeError: LocalizedError {
        case rejected(String)
        var errorDescription: String? {
            if case .rejected(let reason) = self { return reason }
            return "Topology inspection failed"
        }
    }

    private static func diskutil(_ arguments: [String]) throws -> [String: Any] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        // diskutil reads are expected to be small; never parse output larger
        // than the bounded maximum after the process exits.
        let bytes = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0, bytes.count <= 8_388_608,
              let result = try PropertyListSerialization.propertyList(from: bytes, format: nil) as? [String: Any] else {
            throw ProbeError.rejected("Could not read complete diskutil metadata: \(arguments.joined(separator: " "))")
        }
        return result
    }
    private static func appendDiskNames(_ entries: [[String: Any]], into names: inout Set<String>, depth: Int = 0) {
        guard depth <= 8 else { return }
        for entry in entries {
            if let s = entry["DeviceIdentifier"] as? String { names.insert(s) }
            if let subs = entry["Partitions"] as? [[String: Any]] {
                appendDiskNames(subs, into: &names, depth: depth + 1)
            }
        }
    }
    private static func claimObservation(_ name: String) -> Bool? {
        guard let session = DASessionCreate(kCFAllocatorDefault) else { return nil }
        let disk = name.withCString { DADiskCreateFromBSDName(kCFAllocatorDefault, session, $0) }
        guard let disk else { return nil }
        return DADiskIsClaimed(disk)
    }

    static func inspect(_ target: String) throws -> PhysicalDiskTopologyReport {
        guard BrokerAuthorizationPolicy.isValidBSDName(target) else {
            throw ProbeError.rejected("Whole-disk BSD name required")
        }
        let list = try diskutil(["list", "-plist"])
        let apfs = try diskutil(["apfs", "list", "-plist"])
        let root = try diskutil(["info", "-plist", "/"])
        guard let hostRoot = root["DeviceIdentifier"] as? String else {
            throw ProbeError.rejected("Host root media is unidentifiable")
        }
        guard let allDisks = list["AllDisksAndPartitions"] as? [[String: Any]],
              let targetEntry = allDisks.first(where: { $0["DeviceIdentifier"] as? String == target }) else {
            throw ProbeError.rejected("Target absent from diskutil list")
        }
        var names: Set<String> = []
        appendDiskNames([targetEntry], into: &names)
        if let containers = apfs["Containers"] as? [[String: Any]] {
            for container in containers {
                guard let stores = container["PhysicalStores"] as? [[String: Any]] else { continue }
                let storeNames = stores.compactMap { $0["DeviceIdentifier"] as? String ?? $0["PhysicalStore"] as? String }
                if storeNames.contains(where: { names.contains($0.replacingOccurrences(of: "/dev/", with: "")) }),
                   let volumes = container["Volumes"] as? [[String: Any]] {
                    for v in volumes {
                        if let id = v["DeviceIdentifier"] as? String ?? v["APFSVolumeDisk"] as? String {
                            names.insert(id)
                        }
                    }
                }
            }
        }
        guard names.count <= 128, !names.isEmpty else {
            throw ProbeError.rejected("Unexpected number of child devices")
        }
        var info: [String: [String: Any]] = [:]
        for name in names.sorted() {
            guard name.range(of: #"^disk(0|[1-9][0-9]*)(s[0-9]+)*$"#, options: .regularExpression) != nil else {
                throw ProbeError.rejected("Unexpected device identifier in storage graph")
            }
            info[name] = try diskutil(["info", "-plist", name])
        }
        let base = PhysicalDiskTopologyProof.analyze(target: target, diskList: list,
            apfsList: apfs, info: info, hostRootBSD: hostRoot)
        let claimed = claimObservation(target)
        var denials = base.reasons
        var limitations = base.limitations
        if claimed == true { denials.append("Disk Arbitration reports disk already claimed") }
        else if claimed == nil { limitations.append("Disk Arbitration claim state unavailable") }
        let verdict: PhysicalDiskTopologyReport.Verdict = !denials.isEmpty ? .denied :
            (limitations.isEmpty ? .candidateUnclaimed : .inconclusive)
        return .init(requestedBSD: base.requestedBSD, verdict: verdict,
            descendants: base.descendants, apfsContainers: base.apfsContainers,
            apfsVolumes: base.apfsVolumes, hasAPFS: base.hasAPFS,
            containsHostRoot: base.containsHostRoot, mountedDevices: base.mountedDevices,
            reasons: denials, limitations: limitations)
    }
}
