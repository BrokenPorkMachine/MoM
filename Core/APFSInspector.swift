import Foundation

/// Conservative APFS topology reader. No assumptions about bootability are made.
/// Invokes only `diskutil apfs list -plist` and records uncertain data as optional.
struct APFSVolumeRecord: Identifiable, Codable, Hashable, Sendable {
    var id: String { deviceIdentifier }
    let deviceIdentifier: String
    let volumeUUID: String?
    let volumeGroupUUID: String?
    let name: String
    let roles: [String]
    let mountPoint: String?
    let encrypted: Bool?
}

struct APFSContainerRecord: Identifiable, Codable, Hashable, Sendable {
    var id: String { containerIdentifier }
    let containerIdentifier: String
    let containerUUID: String?
    let physicalStores: [String]
    let volumes: [APFSVolumeRecord]
}

struct APFSTopology: Codable, Sendable {
    let containers: [APFSContainerRecord]
    let warnings: [String]
    static let empty = APFSTopology(containers: [], warnings: [])
}

/// Parsing is separate from process execution for fixture-based verification.
enum APFSPlistDecoder {
    static func decode(_ root: [String: Any]) -> APFSTopology {
        guard let raw = root["Containers"] as? [[String: Any]] else {
            return .init(containers: [], warnings: ["APFS containers missing or unsupported diskutil plist layout"])
        }
        var warnings: [String] = []
        let containers = raw.compactMap { container -> APFSContainerRecord? in
            guard let id = firstString(container, ["ContainerReference", "APFSContainerReference"]) else {
                warnings.append("Skipped APFS container without a device reference")
                return nil
            }
            let stores = (container["PhysicalStores"] as? [[String: Any]] ?? []).compactMap {
                firstString($0, ["DeviceIdentifier", "PhysicalStore", "DiskIdentifier"])
            }
            let volumes = (container["Volumes"] as? [[String: Any]] ?? []).compactMap { vol -> APFSVolumeRecord? in
                guard let disk = firstString(vol, ["DeviceIdentifier", "APFSVolumeDisk", "VolumeIdentifier"]) else {
                    warnings.append("Skipped APFS volume without a device identifier in \(id)")
                    return nil
                }
                var roles: [String] = []
                if let many = vol["Roles"] as? [String] { roles = many }
                else if let one = firstString(vol, ["Role", "APFSVolumeRole"]) { roles = [one] }
                return .init(deviceIdentifier: disk,
                             volumeUUID: firstString(vol, ["APFSVolumeUUID", "VolumeUUID"]),
                             volumeGroupUUID: firstString(vol, ["APFSVolumeGroupUUID", "VolumeGroupUUID"]),
                             name: firstString(vol, ["Name", "VolumeName"]) ?? disk,
                             roles: roles,
                             mountPoint: firstString(vol, ["MountPoint"]),
                             encrypted: vol["Encryption"] as? Bool ?? vol["Encrypted"] as? Bool)
            }
            return .init(containerIdentifier: id,
                         containerUUID: firstString(container, ["APFSContainerUUID", "ContainerUUID"]),
                         physicalStores: stores, volumes: volumes)
        }
        return .init(containers: containers, warnings: warnings)
    }

    private static func firstString(_ dictionary: [String: Any], _ keys: [String]) -> String? {
        for key in keys {
            if let value = dictionary[key] as? String, !value.isEmpty { return value }
        }
        return nil
    }
}

struct APFSInspector: Sendable {
    func inspect() async throws -> APFSTopology {
        try await Task.detached(priority: .utility) {
            let root = try DiskutilProcess.propertyList(["apfs", "list", "-plist"])
            return APFSPlistDecoder.decode(root)
        }.value
    }
}
