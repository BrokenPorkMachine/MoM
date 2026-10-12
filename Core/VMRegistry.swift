import Foundation

enum VMInstallState: String, Codable { case provisioning, installing, installed, failed }

struct ManagedVMManifest: Codable, Identifiable {
    let version: Int
    let id: UUID
    let createdAt: Date
    var diskSizeGiB: Int
    var state: VMInstallState
    var lastFailure: String?
    var guestOS: VMGuestOS = .macOS
    var installationMediaPath: String?
    var driverMediaPath: String?
    var qemu: VMQEMUSettings?

    init(version: Int, id: UUID, createdAt: Date, diskSizeGiB: Int, state: VMInstallState, lastFailure: String?,
         guestOS: VMGuestOS = .macOS, installationMediaPath: String? = nil, driverMediaPath: String? = nil,
         qemu: VMQEMUSettings? = nil) {
        self.version = version; self.id = id; self.createdAt = createdAt; self.diskSizeGiB = diskSizeGiB
        self.state = state; self.lastFailure = lastFailure; self.guestOS = guestOS
        self.installationMediaPath = installationMediaPath; self.driverMediaPath = driverMediaPath; self.qemu = qemu
    }

    private enum CodingKeys: String, CodingKey {
        case version, id, createdAt, diskSizeGiB, state, lastFailure, guestOS, installationMediaPath, driverMediaPath, qemu
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        version = try values.decode(Int.self, forKey: .version)
        id = try values.decode(UUID.self, forKey: .id)
        createdAt = try values.decode(Date.self, forKey: .createdAt)
        diskSizeGiB = try values.decode(Int.self, forKey: .diskSizeGiB)
        state = try values.decode(VMInstallState.self, forKey: .state)
        lastFailure = try values.decodeIfPresent(String.self, forKey: .lastFailure)
        guestOS = try values.decodeIfPresent(VMGuestOS.self, forKey: .guestOS) ?? .macOS
        installationMediaPath = try values.decodeIfPresent(String.self, forKey: .installationMediaPath)
        driverMediaPath = try values.decodeIfPresent(String.self, forKey: .driverMediaPath)
        qemu = try values.decodeIfPresent(VMQEMUSettings.self, forKey: .qemu)
    }
}

enum VMRegistry {
    static func read(at folder: URL) throws -> ManagedVMManifest {
        let record = try JSONDecoder().decode(ManagedVMManifest.self, from: Data(contentsOf: folder.appendingPathComponent("manifest.json")))
        guard (1...3).contains(record.version), (64...2048).contains(record.diskSizeGiB) else {
            throw NSError(domain: "VolumeBoot.Registry", code: 1, userInfo: [NSLocalizedDescriptionKey:
                "This VM manifest has an unsupported version or boot disk capacity. Keep its files and open it with a compatible release."])
        }
        return record
    }
    static func write(_ manifest: ManagedVMManifest, at folder: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(manifest).write(to: folder.appendingPathComponent("manifest.json"), options: .atomic)
    }
    /// Enumerates only immediate child bundles of a user-selected parent directory.
    static func discover(in directory: URL) -> [(url: URL, record: ManagedVMManifest)] {
        guard let children = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else { return [] }
        return children.compactMap { url in
            guard (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true,
                  let record = try? read(at: url) else { return nil }
            return (url: url, record: record)
        }.sorted { $0.record.createdAt > $1.record.createdAt }
    }
}

enum VMBackupError: LocalizedError {
    case invalidBackup, backupExists, destinationExists, unsupportedVersion
    case missingExternalDisk(String), unsafeWorkspace

    var errorDescription: String? {
        switch self {
        case .invalidBackup: return "The selected VM backup is missing or invalid."
        case .backupExists: return "The backup destination already exists."
        case .destinationExists: return "The restore destination must not already exist."
        case .unsupportedVersion: return "This VM backup format is not supported by this release."
        case .missingExternalDisk(let path): return "An external disk required by this backup is missing: " + path
        case .unsafeWorkspace: return "The VM workspace contains an unsafe symbolic link."
        }
    }
}

struct VMBackupDescriptor: Codable {
    let version: Int
    let createdAt: Date
    let manifest: ManagedVMManifest
    let externalDisks: [ExternalDisk]

    struct ExternalDisk: Codable {
        let originalPath: String
        let backupPath: String
    }
}

/// Creates and restores stopped VM workspaces. The backup keeps the complete
/// workspace (including firmware, platform identity, auxiliary storage, and TPM
/// state) and separately copies disk images referenced outside that workspace.
enum VMBackupService {
    private static let descriptorName = "backup.json"
    private static let workspaceName = "workspace"
    private static let externalName = "external-disks"

    static func create(from folder: URL, to backup: URL) throws {
        guard !FileManager.default.fileExists(atPath: backup.path) else { throw VMBackupError.backupExists }
        let manifest = try VMRegistry.read(at: folder)
        let hardware = try VMHardwareStore.load(from: folder)
        let root = folder.standardizedFileURL.resolvingSymlinksInPath()
        guard root.path != "/dev", !root.path.hasPrefix("/dev/") else { throw VMBackupError.unsafeWorkspace }
        try rejectSymlinks(in: root)

        let staging = backup.deletingLastPathComponent().appendingPathComponent(".\(backup.lastPathComponent).(UUID().uuidString).tmp")
        let fm = FileManager.default
        defer { try? fm.removeItem(at: staging) }
        try fm.createDirectory(at: staging, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let workspace = staging.appendingPathComponent(workspaceName)
        try fm.copyItem(at: root, to: workspace)

        var external: [VMBackupDescriptor.ExternalDisk] = []
        var externalURLs: [URL] = []
        let boot = hardware.bootDiskURL(in: root).standardizedFileURL.resolvingSymlinksInPath()
        if !isInside(boot, root) { externalURLs.append(boot) }
        externalURLs.append(contentsOf: hardware.additionalDisks.map { URL(fileURLWithPath: $0.path).standardizedFileURL.resolvingSymlinksInPath() })
        var seen = Set<String>()
        for (index, url) in externalURLs.enumerated() {
            guard seen.insert(url.path).inserted else { continue }
            guard fm.fileExists(atPath: url.path) else { throw VMBackupError.missingExternalDisk(url.path) }
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { throw VMBackupError.missingExternalDisk(url.path) }
            let name = String(index) + "-" + url.lastPathComponent.replacingOccurrences(of: "/", with: "_")
            let relative = externalName + "/" + name
            let target = staging.appendingPathComponent(relative)
            try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try fm.copyItem(at: url, to: target)
            external.append(.init(originalPath: url.path, backupPath: relative))
        }

        let descriptor = VMBackupDescriptor(version: 1, createdAt: Date(), manifest: manifest, externalDisks: external)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(descriptor).write(to: staging.appendingPathComponent(descriptorName), options: .atomic)
        try fm.moveItem(at: staging, to: backup)
    }

    static func restore(from backup: URL, to destination: URL) throws {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: destination.path) else { throw VMBackupError.destinationExists }
        let descriptorURL = backup.appendingPathComponent(descriptorName)
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        guard let descriptor = try? decoder.decode(VMBackupDescriptor.self, from: Data(contentsOf: descriptorURL)), descriptor.version == 1 else {
            throw VMBackupError.invalidBackup
        }
        let workspace = backup.appendingPathComponent(workspaceName)
        guard fm.fileExists(atPath: workspace.appendingPathComponent("manifest.json").path) else { throw VMBackupError.invalidBackup }
        try fm.copyItem(at: workspace, to: destination)
        do {
            var mapping: [String: String] = [:]
            let externalDestination = destination.deletingLastPathComponent().appendingPathComponent(destination.lastPathComponent + ".external-disks")
            if !descriptor.externalDisks.isEmpty {
                try fm.createDirectory(at: externalDestination, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                for entry in descriptor.externalDisks {
                    let source = backup.appendingPathComponent(entry.backupPath)
                    guard fm.fileExists(atPath: source.path) else { throw VMBackupError.invalidBackup }
                    let target = externalDestination.appendingPathComponent(URL(fileURLWithPath: entry.backupPath).lastPathComponent)
                    try fm.copyItem(at: source, to: target)
                    mapping[entry.originalPath] = target.path
                }
            }
            if !mapping.isEmpty {
                var hardware = try VMHardwareStore.load(from: destination)
                if let boot = hardware.bootDiskPath { hardware.bootDiskPath = mapping[URL(fileURLWithPath: boot).standardizedFileURL.resolvingSymlinksInPath().path] }
                hardware.additionalDisks = hardware.additionalDisks.map { disk in
                    var copy = disk
                    copy.path = mapping[URL(fileURLWithPath: disk.path).standardizedFileURL.resolvingSymlinksInPath().path] ?? disk.path
                    return copy
                }
                try VMHardwareStore.save(hardware, to: destination)
            }
            _ = try VMRegistry.read(at: destination)
        } catch {
            try? fm.removeItem(at: destination)
            throw error
        }
    }

    private static func isInside(_ file: URL, _ root: URL) -> Bool {
        file.path == root.path || file.path.hasPrefix(root.path + "/")
    }

    private static func rejectSymlinks(in folder: URL) throws {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: folder, includingPropertiesForKeys: [.isSymbolicLinkKey], options: []) else { return }
        for case let url as URL in enumerator where (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
            throw VMBackupError.unsafeWorkspace
        }
    }
}

