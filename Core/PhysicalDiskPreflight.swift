import Foundation

/// Read-only advisory preflight; never authorizes opening /dev disks.
struct PhysicalDiskPreflightResult: Sendable {
    let bsdName: String
    let wholeDisk: String
    let advisoryChecksPassed: Bool
    let reasons: [String]
}

struct PhysicalDiskPreflight: Sendable {
    enum Failure: LocalizedError {
        case invalidName, invalidResponse, commandFailed(Int32)
        var errorDescription: String? {
            switch self {
            case .invalidName: return "Invalid disk name"
            case .invalidResponse: return "Unable to obtain trustworthy disk metadata"
            case .commandFailed(let status): return "diskutil info failed: \(status)"
            }
        }
    }

    static func validName(_ name: String) -> Bool {
        name.range(of: #"^disk[0-9]+(s[0-9]+)*$"#, options: .regularExpression) != nil
    }
    func inspect(_ name: String) async throws -> PhysicalDiskPreflightResult {
        guard Self.validName(name) else { throw Failure.invalidName }
        return try await Task.detached(priority: .utility) { try Self.inspectSynchronously(name) }.value
    }
    private static func info(_ name: String) throws -> [String: Any] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
        process.arguments = ["info", "-plist", name]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        let bytes = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw Failure.commandFailed(process.terminationStatus) }
        guard bytes.count <= 1_048_576,
              let values = try PropertyListSerialization.propertyList(from: bytes, format: nil) as? [String: Any] else {
            throw Failure.invalidResponse
        }
        return values
    }
    private static func inspectSynchronously(_ name: String) throws -> PhysicalDiskPreflightResult {
        let values = try info(name)
        guard (values["DeviceIdentifier"] as? String) == name else { throw Failure.invalidResponse }
        let wholeName = (values["ParentWholeDisk"] as? String) ?? name
        guard validName(wholeName), let wholeInfo = try? info(wholeName),
              (wholeInfo["DeviceIdentifier"] as? String) == wholeName,
              (wholeInfo["WholeDisk"] as? Bool) == true else { throw Failure.invalidResponse }

        // diskutil info on the selected volume is never sufficient to establish
        // that the parent device has no mounted children or APFS physical stores.
        // Fail closed on all such unknowns; the privileged service must obtain
        // and verify a complete topology using DiskArbitration/IOKit.
        let snapshot = PhysicalDiskSafetySnapshot(
            requestedBSD: name, wholeBSD: wholeName,
            isWholeDisk: (values["WholeDisk"] as? Bool) == true,
            isInternal: wholeInfo["Internal"] as? Bool,
            isVirtual: (wholeInfo["VirtualOrPhysical"] as? String).map { $0 == "Virtual" },
            isHostRootStore: nil,
            hasMountedDescendant: nil,
            hasAPFSPhysicalStore: nil,
            hasStableIdentity: false,
            expectedIdentityMatches: false
        )
        switch PhysicalDiskSafetyPolicy.evaluate(snapshot) {
        case .advisoryCandidate:
            return PhysicalDiskPreflightResult(bsdName: name, wholeDisk: wholeName,
                advisoryChecksPassed: true, reasons: ["Preflight observations passed; this does not authorize physical-disk access"])
        case .denied(let reasons):
            return PhysicalDiskPreflightResult(bsdName: name, wholeDisk: wholeName,
                advisoryChecksPassed: false, reasons: reasons)
        }
    }
}
