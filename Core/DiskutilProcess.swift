import Foundation

/// A narrowly scoped read-only `diskutil` executor. Never pass untrusted UI arguments.
enum DiskutilProcess {
    static func isApproved(_ arguments: [String]) -> Bool {
        if arguments == ["list", "-plist"] || arguments == ["apfs", "list", "-plist"] { return true }
        return arguments.count == 3 && arguments[0] == "info" && arguments[1] == "-plist" &&
            arguments[2].range(of: #"^disk[0-9]+(s[0-9]+)*$"#, options: .regularExpression) != nil
    }

    enum Failure: LocalizedError {
        case nonzeroExit(Int32), invalidPlist, tooMuchOutput, timedOut
        var errorDescription: String? {
            switch self {
            case .nonzeroExit(let status): return "diskutil exited with status \(status)"
            case .invalidPlist: return "diskutil returned malformed property-list data"
            case .tooMuchOutput: return "diskutil output exceeded its limit"
            case .timedOut: return "diskutil did not finish before its deadline"
            }
        }
    }
    static func propertyList(_ arguments: [String], timeout: TimeInterval = 15,
                             maximumOutputBytes: Int = 16 * 1024 * 1024) throws -> [String: Any] {
        precondition(isApproved(arguments), "Only approved read-only diskutil subcommands are permitted")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
        process.arguments = arguments
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice
        try process.run()
        let lock = NSLock()
        var data = Data()
        var timedOut = false
        let finished = DispatchSemaphore(value: 0)
        stdout.fileHandleForReading.readabilityHandler = { handle in
            guard let chunk = try? handle.read(upToCount: 64 * 1024), !chunk.isEmpty else {
                finished.signal()
                return
            }
            lock.lock()
            data.append(chunk)
            let tooLarge = data.count > maximumOutputBytes
            lock.unlock()
            if tooLarge {
                process.terminate()
                finished.signal()
            }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
            lock.lock(); timedOut = true; lock.unlock()
            if process.isRunning { process.terminate() }
            finished.signal()
        }
        _ = finished.wait(timeout: .now() + timeout + 2)
        stdout.fileHandleForReading.readabilityHandler = nil
        process.waitUntilExit()
        lock.lock(); let output = data; let deadlineExceeded = timedOut; lock.unlock()
        if deadlineExceeded { throw Failure.timedOut }
        guard process.terminationStatus == 0 else { throw Failure.nonzeroExit(process.terminationStatus) }
        guard output.count <= maximumOutputBytes else { throw Failure.tooMuchOutput }
        guard let plist = try PropertyListSerialization.propertyList(from: output, format: nil) as? [String: Any] else {
            throw Failure.invalidPlist
        }
        return plist
    }
}
