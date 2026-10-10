import Foundation

/// Pure, fixture-testable inventory validation. This is an advisory *proof of
/// observation*, never authorization to open a raw disk. The daemon must repeat
/// checks while holding a Disk Arbitration claim before any APFS grant is enabled.
struct PhysicalDiskTopologyReport: Codable, Equatable, Sendable {
    enum Verdict: String, Codable, Sendable {
        case inconclusive
        case denied
        case candidateUnclaimed
    }
    let requestedBSD: String
    let verdict: Verdict
    let descendants: [String]
    let apfsContainers: [String]
    let apfsVolumes: [String]
    let hasAPFS: Bool
    let containsHostRoot: Bool?
    let mountedDevices: [String]
    let reasons: [String]
    let limitations: [String]
}

enum PhysicalDiskTopologyProof {
    private static func string(_ d: [String: Any], _ keys: [String]) -> String? {
        for key in keys {
            if let s = d[key] as? String, !s.isEmpty { return s }
        }
        return nil
    }
    private static func normalizedBSD(_ s: String?) -> String? {
        guard let s else { return nil }
        let value = s.hasPrefix("/dev/") ? String(s.dropFirst(5)) : s
        return value.range(of: #"^disk(0|[1-9][0-9]*)(s[0-9]+)*$"#, options: .regularExpression) != nil ? value : nil
    }
    private static func name(_ d: [String: Any]) -> String? {
        normalizedBSD(string(d, ["DeviceIdentifier", "PhysicalStore", "DiskIdentifier", "APFSVolumeDisk", "VolumeIdentifier"]))
    }
    private static func roles(_ d: [String: Any]) -> [String] {
        if let a = d["Roles"] as? [String] { return a }
        if let s = string(d, ["Role", "APFSVolumeRole"]) { return [s] }
        return []
    }

    /// - Parameters:
    ///   - diskList: output of `diskutil list -plist`.
    ///   - apfsList: output of `diskutil apfs list -plist` (not optional in an authoritative probe).
    ///   - info: `diskutil info -plist <bsd>` for every observed target descendant
    ///           and synthesized APFS volume. Missing entries always fail closed.
    ///   - hostRootBSD: device of `diskutil info -plist /` (snapshot names allowed).
    static func analyze(target: String,
                        diskList: [String: Any],
                        apfsList: [String: Any]?,
                        info: [String: [String: Any]],
                        hostRootBSD: String?) -> PhysicalDiskTopologyReport {
        var denials: [String] = []
        var limitations: [String] = []
        var nodes = Set<String>()
        var containers = Set<String>()
        var volumes = Set<String>()
        var mounted = Set<String>()
        var anyAPFS = false
        var hostRoot: Bool? = nil
        guard let normalized = normalizedBSD(target), target == normalized,
              target.range(of: #"^disk(0|[1-9][0-9]*)$"#, options: .regularExpression) != nil else {
            return .init(requestedBSD: target, verdict: .denied, descendants: [], apfsContainers: [], apfsVolumes: [], hasAPFS: false, containsHostRoot: nil, mountedDevices: [], reasons: ["Invalid whole-disk identifier"], limitations: [])
        }
        guard let disks = diskList["AllDisksAndPartitions"] as? [[String: Any]] else {
            return .init(requestedBSD: target, verdict: .inconclusive, descendants: [], apfsContainers: [], apfsVolumes: [], hasAPFS: false, containsHostRoot: nil, mountedDevices: [], reasons: ["diskutil disk list missing"], limitations: [])
        }
        guard let matching = disks.filter({ name($0) == target }).first,
              disks.filter({ name($0) == target }).count == 1 else {
            return .init(requestedBSD: target, verdict: .inconclusive, descendants: [], apfsContainers: [], apfsVolumes: [], hasAPFS: false, containsHostRoot: nil, mountedDevices: [], reasons: ["Target absent or duplicated in disk topology"], limitations: [])
        }
        func collect(_ node: [String: Any], _ depth: Int) {
            if depth > 8 { limitations.append("Disk topology recursion limit exceeded"); return }
            guard let id = name(node), nodes.insert(id).inserted else {
                limitations.append("Missing or duplicate descendant identifier"); return
            }
            if let p = node["Partitions"] as? [[String: Any]] {
                for part in p { collect(part, depth + 1) }
            } else if node["Partitions"] != nil {
                limitations.append("Unrecognized partition layout on \(id)")
            } else if (node["Content"] as? String ?? "").lowercased().contains("partition") {
                limitations.append("Partition map not enumerated on \(id)")
            }
        }
        collect(matching, 0)
        guard let whole = info[target], string(whole, ["DeviceIdentifier"]) == target else {
            return .init(requestedBSD: target, verdict: .inconclusive, descendants: nodes.sorted(), apfsContainers: [], apfsVolumes: [], hasAPFS: false, containsHostRoot: nil, mountedDevices: [], reasons: ["Whole disk metadata unavailable or changed"], limitations: limitations)
        }
        if whole["WholeDisk"] as? Bool != true { denials.append("Target is not confirmed whole disk") }
        if whole["Internal"] as? Bool != false { denials.append("Internal or unclassified media") }
        if (whole["DeviceLocation"] as? String) != "External" { denials.append("External connection not confirmed") }
        if (whole["VirtualOrPhysical"] as? String) != "Physical" { denials.append("Physical media not confirmed") }
        if (whole["TotalSize"] as? NSNumber)?.uint64Value ?? 0 == 0 { limitations.append("Disk size not verified") }

        guard let apfsList, let allContainers = apfsList["Containers"] as? [[String: Any]] else {
            return .init(requestedBSD: target, verdict: .inconclusive, descendants: nodes.sorted(), apfsContainers: [], apfsVolumes: [], hasAPFS: false, containsHostRoot: nil, mountedDevices: [], reasons: denials, limitations: limitations + ["Full APFS topology unavailable"])
        }
        for container in allContainers {
            guard let ref = string(container, ["ContainerReference", "APFSContainerReference"]),
                  let stores = container["PhysicalStores"] as? [[String: Any]],
                  !stores.isEmpty, let listedVolumes = container["Volumes"] as? [[String: Any]] else {
                limitations.append("APFS container metadata incomplete")
                continue
            }
            var storeIDs: Set<String> = []
            for store in stores {
                if let id = name(store) { storeIDs.insert(id) }
                else { limitations.append("APFS physical store identity missing in \(ref)") }
            }
            if !storeIDs.isDisjoint(with: nodes) {
                anyAPFS = true
                containers.insert(ref)
                // Every physical store belonging to a selected APFS container must
                // be on the requested whole disk. No Fusion/multi-store partial grants.
                if !storeIDs.isSubset(of: nodes) { denials.append("APFS container spans another physical disk") }
                for volume in listedVolumes {
                    if let id = name(volume) {
                        volumes.insert(id)
                        let roleList = roles(volume)
                        if roleList.isEmpty { limitations.append("APFS role unavailable for \(id)") }
                    } else { limitations.append("APFS volume identifier absent in \(ref)") }
                }
            }
        }
        // Include both partition descendants and synthesized APFS volumes.
        for id in nodes.union(volumes) {
            guard let metadata = info[id], string(metadata, ["DeviceIdentifier"]) == id else {
                limitations.append("Missing or changed per-device metadata: \(id)")
                continue
            }
            if let isMounted = metadata["Mounted"] as? Bool {
                if isMounted { mounted.insert(id) }
            } else {
                // Physical stores may not be mountable. Partition and synthesized
                // volume objects must have an explicit mount-state proof.
                let isLeaf = id != target
                if isLeaf { limitations.append("Mount state unknown for \(id)") }
            }
            if let mountPoint = metadata["MountPoint"] as? String, !mountPoint.isEmpty {
                mounted.insert(id)
            }
        }
        if !mounted.isEmpty { denials.append("Mounted guest-related volumes: \(mounted.sorted().joined(separator: ", "))") }
        if let root = normalizedBSD(hostRootBSD) {
            // Snapshot-root identifiers may append an additional sN suffix.
            var matches = nodes.contains(where: { root == $0 || root.hasPrefix($0 + "s") })
            if !matches {
                matches = volumes.contains(where: { root == $0 || root.hasPrefix($0 + "s") })
            }
            // Root on a synthesized APFS volume is resolved through container
            // membership above. A missing root-to-store mapping isn't positive proof.
            hostRoot = matches
            if matches { denials.append("Disk contains the active host boot volume") }
        } else { limitations.append("Host root storage identity unavailable") }
        if anyAPFS { limitations.append("APFS disks remain inspection-only pending tested Disk Arbitration claim") }
        if !denials.isEmpty { return .init(requestedBSD: target, verdict: .denied,
            descendants: nodes.sorted(), apfsContainers: containers.sorted(), apfsVolumes: volumes.sorted(),
            hasAPFS: anyAPFS, containsHostRoot: hostRoot, mountedDevices: mounted.sorted(), reasons: denials, limitations: limitations) }
        let result: PhysicalDiskTopologyReport.Verdict = limitations.isEmpty ? .candidateUnclaimed : .inconclusive
        return .init(requestedBSD: target, verdict: result, descendants: nodes.sorted(),
            apfsContainers: containers.sorted(), apfsVolumes: volumes.sorted(), hasAPFS: anyAPFS,
            containsHostRoot: hostRoot, mountedDevices: mounted.sorted(), reasons: denials, limitations: limitations)
    }
}
