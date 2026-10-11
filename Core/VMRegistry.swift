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

