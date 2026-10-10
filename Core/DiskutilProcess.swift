import Foundation

/// A narrowly scoped read-only `diskutil` executor. Never pass untrusted UI arguments.
enum DiskutilProcess {
    enum Failure: LocalizedError {
        case nonzeroExit(Int32), invalidPlist, tooMuchOutput
        var errorDescription: String? {
            switch self {
            case .nonzeroExit(let status): return "diskutil exited with status \(status)"
            case .invalidPlist: return "diskutil returned malformed property-list data"
            case .tooMuchOutput: return "diskutil output exceeded its limit"
            }
        }
    }
    static func propertyList(_ arguments: [String]) throws -> [String: Any] {
        let allowed: [[String]] = [["list", "-plist"], ["apfs", "list", "-plist"]]
        precondition(allowed.contains(arguments), "Only approved read-only diskutil subcommands are permitted")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
        process.arguments = arguments
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw Failure.nonzeroExit(process.terminationStatus) }
        guard data.count <= 16 * 1024 * 1024 else { throw Failure.tooMuchOutput }
        guard let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            throw Failure.invalidPlist
        }
        return plist
    }
}
