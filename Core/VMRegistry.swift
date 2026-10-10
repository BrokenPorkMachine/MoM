import Foundation

enum VMInstallState: String, Codable { case provisioning, installed, failed }

struct ManagedVMManifest: Codable, Identifiable {
    let version: Int
    let id: UUID
    let createdAt: Date
    var diskSizeGiB: Int
    var state: VMInstallState
    var lastFailure: String?
}

enum VMRegistry {
    static func read(at folder: URL) throws -> ManagedVMManifest {
        try JSONDecoder().decode(ManagedVMManifest.self, from: Data(contentsOf: folder.appendingPathComponent("manifest.json")))
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

