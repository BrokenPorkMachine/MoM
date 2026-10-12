import Foundation
import CryptoKit
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

enum VMBackendKind: String, Codable, CaseIterable {
    case qemu = "QEMU"
    case swtpm = "swtpm"
}

struct VMBackendExecutableIdentity: Codable, Equatable, Identifiable {
    let kind: VMBackendKind
    let path: String
    let sha256: String

    var id: String { "\(kind.rawValue)|\(path)|\(sha256)" }
}

enum VMBackendTrustError: LocalizedError {
    case invalidExecutable(String)
    case approvalRequired(String)
    case changedDuringInspection(String)
    case trustStoreUnavailable(String)
    case versionProbeFailed(String)
    case versionProbeTimedOut(String)
    case unsupportedQEMUVersion(String)
    case unsupportedMachine(String)

    var errorDescription: String? {
        switch self {
        case .invalidExecutable(let path): return "Backend executable must be an absolute path to a regular executable file: \(path)"
        case .approvalRequired(let path): return "This workspace uses an unapproved backend executable: \(path). Approve it before starting the VM."
        case .changedDuringInspection(let path): return "Backend executable changed while it was being inspected: \(path)"
        case .trustStoreUnavailable(let reason): return "Backend trust approvals could not be read or saved safely: \(reason)"
        case .versionProbeFailed(let name): return "Could not read a valid version from the approved \(name) executable."
        case .versionProbeTimedOut(let name): return "The approved \(name) executable did not answer its version check within five seconds."
        case .unsupportedQEMUVersion(let version): return "QEMU \(version) is too old or unrecognized. Windows ARM requires QEMU 9.2 or newer."
        case .unsupportedMachine(let machine): return "Unsupported QEMU machine profile: \(machine). This release requires virt-9.2."
        }
    }
}

/// User-level executable trust pins are kept outside imported VM folders. An
/// approval is bound to both the resolved path and the executable's SHA-256.
final class VMBackendExecutableTrustStore {
    static let shared = VMBackendExecutableTrustStore()

    private let fileURL: URL
    private var sessionApprovedIDs = Set<String>()

    init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else if let override = ProcessInfo.processInfo.environment["VOLUMEBOOT_BACKEND_TRUST_FILE"], !override.isEmpty {
            self.fileURL = URL(fileURLWithPath: override)
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            self.fileURL = appSupport.appendingPathComponent("MacOnMac/BackendExecutableTrust.json")
        }
    }

    static func inspect(kind: VMBackendKind, path: String) throws -> VMBackendExecutableIdentity {
        guard path.hasPrefix("/"), !path.contains("\0") else { throw VMBackendTrustError.invalidExecutable(path) }
        let resolved = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath()
        let canonicalPath = resolved.path
        let manager = FileManager.default
        guard let before = try? manager.attributesOfItem(atPath: canonicalPath),
              before[.type] as? FileAttributeType == .typeRegular,
              manager.isExecutableFile(atPath: canonicalPath),
              let fileNumberBefore = before[.systemFileNumber] as? NSNumber,
              let fileSizeBefore = before[.size] as? NSNumber else {
            throw VMBackendTrustError.invalidExecutable(canonicalPath)
        }

        let handle: FileHandle
        do { handle = try FileHandle(forReadingFrom: resolved) }
        catch { throw VMBackendTrustError.invalidExecutable(canonicalPath) }
        defer { try? handle.close() }
        var hasher = SHA256()
        let magic = try handle.read(upToCount: 4) ?? Data()
        let machOMagics: Set<[UInt8]> = [
            [0xcf, 0xfa, 0xed, 0xfe], [0xfe, 0xed, 0xfa, 0xcf],
            [0xca, 0xfe, 0xba, 0xbe], [0xbe, 0xba, 0xfe, 0xca],
            [0xca, 0xfe, 0xba, 0xbf], [0xbf, 0xba, 0xfe, 0xca]
        ]
        guard machOMagics.contains(Array(magic)) else { throw VMBackendTrustError.invalidExecutable(canonicalPath) }
        hasher.update(data: magic)
        while true {
            let chunk = try handle.read(upToCount: 1024 * 1024) ?? Data()
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
        }
        let digest = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        guard let after = try? manager.attributesOfItem(atPath: canonicalPath),
              let fileNumberAfter = after[.systemFileNumber] as? NSNumber,
              let fileSizeAfter = after[.size] as? NSNumber,
              fileNumberBefore == fileNumberAfter, fileSizeBefore == fileSizeAfter,
              (before[.modificationDate] as? Date) == (after[.modificationDate] as? Date) else {
            throw VMBackendTrustError.changedDuringInspection(canonicalPath)
        }
        return VMBackendExecutableIdentity(kind: kind, path: canonicalPath, sha256: digest)
    }

    func isApproved(_ identity: VMBackendExecutableIdentity) throws -> Bool {
        if sessionApprovedIDs.contains(identity.id) { return true }
        return try readApprovedIDs().contains(identity.id)
    }

    func verifyCurrentApproval(kind: VMBackendKind, path: String) throws {
        let current = try Self.inspect(kind: kind, path: path)
        guard try isApproved(current) else { throw VMBackendTrustError.approvalRequired(current.path) }
    }

    func approve(_ identity: VMBackendExecutableIdentity, persistently: Bool) throws {
        guard persistently else { sessionApprovedIDs.insert(identity.id); return }
        var ids = try readApprovedIDs()
        ids.insert(identity.id)
        let directory = fileURL.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
            let data = try JSONEncoder.sorted.encode(ids.sorted())
            try data.write(to: fileURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
        } catch {
            throw VMBackendTrustError.trustStoreUnavailable(error.localizedDescription)
        }
    }

    private func readApprovedIDs() throws -> Set<String> {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        do {
            let directoryAttributes = try FileManager.default.attributesOfItem(atPath: fileURL.deletingLastPathComponent().path)
            guard directoryAttributes[.type] as? FileAttributeType == .typeDirectory,
                  let directoryPermissions = directoryAttributes[.posixPermissions] as? NSNumber,
                  directoryPermissions.intValue & 0o077 == 0,
                  (directoryAttributes[.ownerAccountID] as? NSNumber)?.uint32Value == getuid() else {
                throw VMBackendTrustError.trustStoreUnavailable("approval directory must be private and owned by this account")
            }
            let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
            guard attributes[.type] as? FileAttributeType == .typeRegular,
                  let permissions = attributes[.posixPermissions] as? NSNumber,
                  permissions.intValue & 0o077 == 0,
                  (attributes[.ownerAccountID] as? NSNumber)?.uint32Value == getuid() else {
                throw VMBackendTrustError.trustStoreUnavailable("approval file must be a private regular file")
            }
            let ids = try JSONDecoder().decode([String].self, from: Data(contentsOf: fileURL))
            return Set(ids)
        } catch let error as VMBackendTrustError { throw error }
        catch { throw VMBackendTrustError.trustStoreUnavailable(error.localizedDescription) }
    }
}

private extension JSONEncoder {
    static var sorted: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}

enum VMBackendVersion {
    static func qemu(_ output: String) throws -> (major: Int, minor: Int, patch: Int) {
        let pattern = #"(?i)QEMU emulator version\s+(\d+)\.(\d+)(?:\.(\d+))?"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: output, range: NSRange(output.startIndex..., in: output)),
              let majorRange = Range(match.range(at: 1), in: output),
              let minorRange = Range(match.range(at: 2), in: output),
              let major = Int(output[majorRange]), let minor = Int(output[minorRange]) else {
            throw VMBackendTrustError.versionProbeFailed("QEMU")
        }
        let patch = Range(match.range(at: 3), in: output).flatMap { Int(output[$0]) } ?? 0
        guard major > 9 || (major == 9 && minor >= 2) else {
            throw VMBackendTrustError.unsupportedQEMUVersion("\(major).\(minor).\(patch)")
        }
        return (major, minor, patch)
    }

    static func swtpm(_ output: String) throws -> (major: Int, minor: Int, patch: Int) {
        let pattern = #"(?i)(?:swtpm|TPM emulator) version\s+(\d+)\.(\d+)(?:\.(\d+))?"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: output, range: NSRange(output.startIndex..., in: output)),
              let majorRange = Range(match.range(at: 1), in: output),
              let minorRange = Range(match.range(at: 2), in: output),
              let major = Int(output[majorRange]), let minor = Int(output[minorRange]) else {
            throw VMBackendTrustError.versionProbeFailed("swtpm")
        }
        let patch = Range(match.range(at: 3), in: output).flatMap { Int(output[$0]) } ?? 0
        return (major, minor, patch)
    }
}

enum VMBackendVersionProbe {
    static func output(path: String, arguments: [String], name: String, timeout: TimeInterval = 5) throws -> String {
        let process = Process()
        let pipe = Pipe()
        let completed = DispatchSemaphore(value: 0)
        let lock = NSLock()
        var captured = Data()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = pipe
        process.terminationHandler = { _ in completed.signal() }
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { return }
            lock.lock()
            if captured.count < 8192 { captured.append(chunk.prefix(8192 - captured.count)) }
            lock.unlock()
        }
        do { try process.run() }
        catch { pipe.fileHandleForReading.readabilityHandler = nil; throw VMBackendTrustError.versionProbeFailed(name) }
        if completed.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            if completed.wait(timeout: .now() + 0.5) == .timedOut {
                #if canImport(Darwin)
                _ = kill(process.processIdentifier, SIGKILL)
                #endif
                _ = completed.wait(timeout: .now() + 1)
            }
            pipe.fileHandleForReading.readabilityHandler = nil
            throw VMBackendTrustError.versionProbeTimedOut(name)
        }
        pipe.fileHandleForReading.readabilityHandler = nil
        while true {
            let tail = pipe.fileHandleForReading.availableData
            if tail.isEmpty { break }
            lock.lock()
            if captured.count < 8192 { captured.append(tail.prefix(8192 - captured.count)) }
            lock.unlock()
        }
        lock.lock(); let output = captured; lock.unlock()
        guard process.terminationStatus == 0,
              let string = String(data: output, encoding: .utf8), !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw VMBackendTrustError.versionProbeFailed(name)
        }
        return string
    }
}
