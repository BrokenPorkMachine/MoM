import Foundation

/// Deliberately narrow data-only protocol. No guest or host remote command execution.
struct VBExchangeMessage: Codable, Identifiable {
    let id: UUID
    let timestamp: Date
    let from: String
    let body: String
}

struct VBGuestHeartbeat: Codable {
    let protocolVersion: Int
    let timestamp: Date
    let hostname: String
    let operatingSystem: String
}

enum HostGuestExchange {
    static let rootName = "Exchange"
    static let maxMessageBytes = 16_384
    static let maxFileBytes: UInt64 = 64 * 1024 * 1024

    static func root(for vmFolder: URL) -> URL { vmFolder.appendingPathComponent(rootName, isDirectory: true) }

    static func createIfNeeded(in vmFolder: URL) throws {
        let root = root(for: vmFolder)
        for component in ["host-to-guest", "guest-to-host", "host-files", "guest-files"] {
            try FileManager.default.createDirectory(at: root.appendingPathComponent(component, isDirectory: true), withIntermediateDirectories: true)
        }
    }

    static func send(_ message: String, from origin: String, in vmFolder: URL) throws {
        guard origin == "host" || origin == "guest" else { throw NSError(domain: "VolumeBoot.Exchange", code: 1) }
        guard !message.isEmpty, message.utf8.count <= maxMessageBytes else { throw NSError(domain: "VolumeBoot.Exchange", code: 2) }
        let dir = root(for: vmFolder).appendingPathComponent(origin == "host" ? "host-to-guest" : "guest-to-host", isDirectory: true)
        guard FileManager.default.fileExists(atPath: dir.path) else { throw CocoaError(.fileNoSuchFile) }
        let record = VBExchangeMessage(id: UUID(), timestamp: Date(), from: origin, body: message)
        try JSONEncoder().encode(record).write(to: dir.appendingPathComponent("\(record.id.uuidString).json"), options: .atomic)
    }

    static func receive(for recipient: String, in vmFolder: URL, limit: Int = 100) -> [VBExchangeMessage] {
        let dir = root(for: vmFolder).appendingPathComponent(recipient == "host" ? "guest-to-host" : "host-to-guest", isDirectory: true)
        guard let urls = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else { return [] }
        return urls.filter { $0.pathExtension == "json" && UUID(uuidString: $0.deletingPathExtension().lastPathComponent) != nil }
            .prefix(max(0, min(limit, 500)))
            .compactMap { url in
                guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
                      (attributes[.size] as? NSNumber)?.intValue ?? Int.max <= maxMessageBytes + 2_048,
                      let data = try? Data(contentsOf: url) else { return nil }
                return try? JSONDecoder().decode(VBExchangeMessage.self, from: data)
            }.sorted { $0.timestamp > $1.timestamp }
    }

    static func guestHeartbeat(in vmFolder: URL) -> VBGuestHeartbeat? {
        let url = root(for: vmFolder).appendingPathComponent("heartbeat.json")
        guard let data = try? Data(contentsOf: url), data.count <= 4_096 else { return nil }
        return try? JSONDecoder().decode(VBGuestHeartbeat.self, from: data)
    }

    /// Filename is a UUID, never a user-provided basename, to avoid traversal.
    static func stageFile(_ source: URL, from origin: String, in vmFolder: URL) throws -> URL {
        guard origin == "host" || origin == "guest" else { throw NSError(domain: "VolumeBoot.Exchange", code: 2) }
        let values = try source.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .isSymbolicLinkKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true,
              let size = values.fileSize, size >= 0, UInt64(size) <= maxFileBytes else { throw NSError(domain: "VolumeBoot.Exchange", code: 3) }
        let directory = root(for: vmFolder).appendingPathComponent(origin == "host" ? "host-files" : "guest-files", isDirectory: true)
        guard FileManager.default.fileExists(atPath: directory.path) else { throw CocoaError(.fileNoSuchFile) }
        let extensionText = source.pathExtension.lowercased()
        let safeExt = extensionText.range(of: "^[a-z0-9]{1,12}$", options: .regularExpression) != nil ? ".\(extensionText)" : ""
        let output = directory.appendingPathComponent(UUID().uuidString + safeExt)
        try FileManager.default.copyItem(at: source, to: output)
        return output
    }
}
