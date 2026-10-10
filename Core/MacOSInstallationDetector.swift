import Foundation

/// Evidence-based, non-destructive grouping of APFS System and Data volumes.
/// Matching only by volume name is unsafe: use the APFS volume-group UUID when present.
struct MacOSInstallationCandidate: Identifiable, Hashable, Sendable {
    let id: String
    let containerIdentifier: String
    let systemDevice: String
    let systemName: String
    let dataDevice: String?
    let groupUUID: String?
    let evidence: [String]
    let warnings: [String]
    var isVerifiedBootable: Bool { false }
}

enum MacOSInstallationDetector {
    static func detect(_ topology: APFSTopology) -> [MacOSInstallationCandidate] {
        topology.containers.flatMap { container in
            let systems = container.volumes.filter { $0.roles.contains(where: { $0.caseInsensitiveCompare("System") == .orderedSame }) }
            let data = container.volumes.filter { $0.roles.contains(where: { $0.caseInsensitiveCompare("Data") == .orderedSame }) }
            return systems.map { system in
                let sameGroup = data.filter { system.volumeGroupUUID != nil && $0.volumeGroupUUID?.caseInsensitiveCompare(system.volumeGroupUUID!) == .orderedSame }
                let peer = sameGroup.count == 1 ? sameGroup.first : nil
                var warnings: [String] = []
                if system.volumeGroupUUID == nil { warnings.append("No volume-group UUID; Data volume pairing unverified") }
                if sameGroup.count > 1 { warnings.append("Multiple Data volumes share the group UUID") }
                if peer == nil { warnings.append("No uniquely correlated Data volume") }
                warnings.append("System role is not proof of a bootable macOS installation")
                return MacOSInstallationCandidate(id: container.containerIdentifier + ":" + system.deviceIdentifier,
                    containerIdentifier: container.containerIdentifier,
                    systemDevice: system.deviceIdentifier,
                    systemName: system.name,
                    dataDevice: peer?.deviceIdentifier,
                    groupUUID: system.volumeGroupUUID,
                    evidence: ["APFS System role", peer == nil ? "No verified Data pairing" : "Data paired by volume-group UUID"],
                    warnings: warnings)
            }
        }
    }
}
