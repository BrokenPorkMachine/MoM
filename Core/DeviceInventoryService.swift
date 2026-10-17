import Foundation

/// Read-only discovery. diskutil is invoked without mutation subcommands.
struct DeviceInventoryService: Sendable {
    enum InventoryError: LocalizedError {
        case malformedResult
        var errorDescription: String? {
            switch self {
            case .malformedResult: return "diskutil returned an invalid property list"
            }
        }
    }

    func listDevices() async throws -> [StorageDevice] {
        try await Self.scan()
    }

    private static func scan() async throws -> [StorageDevice] {
        let root = try DiskutilProcess.propertyList(["list", "-plist"])
        guard let names = root["AllDisks"] as? [String] else { throw InventoryError.malformedResult }
        // Device identifiers come from diskutil itself, never arbitrary user input.
        // Enumerating diskutil metadata is intentionally read-only and does not imply bootability.
        // Bound concurrent subprocesses so large host inventories do not overwhelm diskutil.
        let concurrency = min(8, max(2, ProcessInfo.processInfo.processorCount))
        let validNames = names.filter { DiskutilProcess.isApproved(["info", "-plist", $0]) }
        let records: [StorageDevice?] = try await TaskDispatchQueue.map(validNames, maxConcurrent: concurrency,
            priority: { name in name == "disk0" ? 0 : 1 },
            resourceKey: { "diskutil:\($0)" }) { name in
            guard let entry = try? DiskutilProcess.propertyList(["info", "-plist", name]) else { return nil }
            let string: (String) -> String = { entry[$0] as? String ?? "" }
            let writable = entry["Writable"] as? Bool ?? false
            let size = (entry["TotalSize"] as? NSNumber)?.uint64Value ?? 0
            return StorageDevice(identifier: name,
                                 name: string("VolumeName").isEmpty ? string("MediaName") : string("VolumeName"),
                                 filesystem: string("FilesystemType"),
                                 mountPoint: string("MountPoint"),
                                 transport: string("BusProtocol"),
                                 isWholeDisk: entry["WholeDisk"] as? Bool ?? false,
                                 isInternal: entry["Internal"] as? Bool ?? false,
                                 isWritable: writable, sizeBytes: size)
        }
        return records.compactMap { $0 }
    }
}
