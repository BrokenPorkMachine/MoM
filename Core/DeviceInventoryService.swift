import Foundation

/// Read-only discovery. diskutil is invoked without mutation subcommands.
struct DeviceInventoryService: Sendable {
    enum InventoryError: LocalizedError {
        case commandFailed(Int32)
        case malformedResult
        var errorDescription: String? {
            switch self {
            case .commandFailed(let code): return "diskutil exited with \(code)"
            case .malformedResult: return "diskutil returned an invalid property list"
            }
        }
    }

    func listDevices() async throws -> [StorageDevice] {
        try await Self.scan()
    }

    private static func diskutil(_ arguments: [String]) throws -> [String: Any] {
        guard arguments.count == 3, arguments[0] == "info", arguments[1] == "-plist",
              arguments[2].range(of: #"^disk[0-9]+(s[0-9]+)*$"#, options: .regularExpression) != nil else {
            throw InventoryError.malformedResult
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw InventoryError.commandFailed(process.terminationStatus) }
        guard let dict = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            throw InventoryError.malformedResult
        }
        return dict
    }

    private static func scan() async throws -> [StorageDevice] {
        let root = try DiskutilProcess.propertyList(["list", "-plist"])
        guard let names = root["AllDisks"] as? [String] else { throw InventoryError.malformedResult }
        // Device identifiers come from diskutil itself, never arbitrary user input.
        // Enumerating diskutil metadata is intentionally read-only and does not imply bootability.
        // Bound concurrent subprocesses so large host inventories do not overwhelm diskutil.
        let concurrency = min(8, max(2, ProcessInfo.processInfo.processorCount))
        let records: [StorageDevice?] = try await TaskDispatchQueue.map(names, maxConcurrent: concurrency,
            priority: { name in name == "disk0" ? 0 : 1 },
            resourceKey: { "diskutil:\($0)" }) { name in
            guard let entry = try? Self.diskutil(["info", "-plist", name]) else { return nil }
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
