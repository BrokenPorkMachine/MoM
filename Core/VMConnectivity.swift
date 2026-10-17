import Foundation

/// Per-VM policy stored in connectivity.json. Paths are user-selected host paths,
/// never raw disk device paths. These settings are applied only at VM startup.
enum VMNetworkMode: String, Codable, CaseIterable, Identifiable {
    case nat, bridged, disconnected
    var id: String { rawValue }
}

enum ReleaseFeaturePolicy {
    static let bridgedNetworkingEnabled = false
}

struct VMConnectivitySettings: Codable, Equatable {
    var version: Int = 1
    var networkMode: VMNetworkMode = .nat
    var bridgedInterfaceID: String? = nil
    var sharedFolderPath: String? = nil
    var shareReadOnly: Bool = true
    var guestToolsEnabled: Bool = false

    static let `default` = VMConnectivitySettings()
}

enum VMConnectivityError: Error, LocalizedError, Equatable {
    case missingBridgedInterface, invalidBridgedInterface, bridgedUnavailableInRelease
    case invalidSharedPath, shareNotDirectory, shareOverlapsVM, shareInDeviceTree
    case unsupportedVersion, policyDenied(String)
    var errorDescription: String? {
        switch self {
        case .missingBridgedInterface: return "Select a physical interface for bridged networking"
        case .invalidBridgedInterface: return "The selected bridge interface is no longer available"
        case .bridgedUnavailableInRelease: return "Bridged networking is unavailable in this release"
        case .invalidSharedPath: return "Shared folder must be an absolute, existing local directory"
        case .shareNotDirectory: return "The selected share is not a directory"
        case .shareOverlapsVM: return "Shared folder cannot be the VM bundle, contain it, or be contained by it"
        case .shareInDeviceTree: return "Raw device paths cannot be shared"
        case .unsupportedVersion: return "Unrecognized connectivity settings version"
        case .policyDenied(let setting): return "An administrator policy disallows \(setting)."
        }
    }
}

/// Pure policy checks usable without Virtualization.framework or a macOS SDK.
enum VMConnectivityPolicy {
    static func verify(_ settings: VMConnectivitySettings, vmFolder: URL, validInterfaces: Set<String> = []) throws {
        guard settings.version == 1 else { throw VMConnectivityError.unsupportedVersion }
        if settings.networkMode == .bridged {
            guard ReleaseFeaturePolicy.bridgedNetworkingEnabled else { throw VMConnectivityError.bridgedUnavailableInRelease }
            guard let id = settings.bridgedInterfaceID, !id.isEmpty else { throw VMConnectivityError.missingBridgedInterface }
            guard validInterfaces.contains(id) else { throw VMConnectivityError.invalidBridgedInterface }
        }
        guard let path = settings.sharedFolderPath, !path.isEmpty else { return }
        guard path.hasPrefix("/"), !path.hasPrefix("/dev/") else { throw VMConnectivityError.invalidSharedPath }
        let share = URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL.resolvingSymlinksInPath()
        let vm = vmFolder.standardizedFileURL.resolvingSymlinksInPath()
        let sharePath = share.path, vmPath = vm.path
        guard sharePath != "/", sharePath != "/dev", !sharePath.hasPrefix("/dev/") else { throw VMConnectivityError.shareInDeviceTree }
        guard sharePath != vmPath && !sharePath.hasPrefix(vmPath + "/") && !vmPath.hasPrefix(sharePath + "/") else {
            throw VMConnectivityError.shareOverlapsVM
        }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: sharePath, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw VMConnectivityError.shareNotDirectory
        }
    }

    /// Stable, locally administered unicast address derived from the VM UUID.
    static func stableMAC(for id: UUID) -> String {
        let bytes = withUnsafeBytes(of: id.uuid) { Array($0) }
        var mac = Array(bytes.prefix(6))
        mac[0] = (mac[0] | 0x02) & 0xFE
        return mac.map { String(format: "%02x", $0) }.joined(separator: ":")
    }
}

enum VMConnectivityStore {
    static let filename = "connectivity.json"
    static func load(from folder: URL) throws -> VMConnectivitySettings {
        let url = folder.appendingPathComponent(filename)
        guard FileManager.default.fileExists(atPath: url.path) else { return .default }
        return try JSONDecoder().decode(VMConnectivitySettings.self, from: Data(contentsOf: url))
    }
    static func save(_ settings: VMConnectivitySettings, to folder: URL) throws {
        guard FileManager.default.fileExists(atPath: folder.path) else {
            throw CocoaError(.fileNoSuchFile)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(settings).write(to: folder.appendingPathComponent(filename), options: .atomic)
    }
}
