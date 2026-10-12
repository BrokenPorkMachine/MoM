import Foundation

enum VMGuestOS: String, Codable, CaseIterable, Identifiable {
    case macOS, linuxARM, windowsARM
    var id: String { rawValue }
    var title: String {
        switch self {
        case .macOS: return "macOS"
        case .linuxARM: return "ARM Linux"
        case .windowsARM: return "Windows ARM"
        }
    }
}

enum VMGuestError: LocalizedError {
    case invalidISO, invalidState, missingTool(String), unsupportedWindowsSettings
    var errorDescription: String? {
        switch self {
        case .invalidISO: return "Choose an existing local ARM64 / AArch64 installation ISO."
        case .invalidState: return "Stop an ARM guest in the installing state before finishing installation."
        case .missingTool(let name): return "Windows ARM requires \(name). Install QEMU and swtpm, or select their paths in Overview."
        case .unsupportedWindowsSettings: return "Windows supports NAT or disconnected networking. Disable workspace sharing, guest tools, and microphone input for this backend."
        }
    }
}

enum VMGuestMedia {
    static func verifyISO(_ url: URL) throws {
        let resolved = url.standardizedFileURL.resolvingSymlinksInPath()
        guard url.isFileURL, url.pathExtension.lowercased() == "iso",
              resolved.path != "/dev", !resolved.path.hasPrefix("/dev/"),
              let values = try? resolved.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
              values.isRegularFile == true, let size = values.fileSize, size >= 512,
              size % 512 == 0 else { throw VMGuestError.invalidISO }
    }
}

struct VMQEMUSettings: Codable, Equatable {
    var executablePath: String
    var swtpmPath: String
    var machine = "virt-9.2"

    static func discover(qemuPath: String = "", swtpmPath: String = "") throws -> VMQEMUSettings {
        func executable(_ requested: String, _ name: String) throws -> String {
            let candidates = requested.isEmpty ? ["/opt/homebrew/bin/\(name)", "/usr/local/bin/\(name)"] : [requested]
            for candidate in candidates {
                if let identity = try? VMBackendExecutableTrustStore.inspect(kind: name == "swtpm" ? .swtpm : .qemu, path: candidate) {
                    return identity.path
                }
            }
            throw VMGuestError.missingTool(name)
        }
        return try VMQEMUSettings(executablePath: executable(qemuPath, "qemu-system-aarch64"),
                                  swtpmPath: executable(swtpmPath, "swtpm"))
    }

    func firstUnapprovedExecutable(using trustStore: VMBackendExecutableTrustStore = .shared) throws -> VMBackendExecutableIdentity? {
        for (kind, path) in [(VMBackendKind.qemu, executablePath), (.swtpm, swtpmPath)] {
            let identity = try VMBackendExecutableTrustStore.inspect(kind: kind, path: path)
            if try !trustStore.isApproved(identity) { return identity }
        }
        return nil
    }

    func verifyApprovedVersions(using trustStore: VMBackendExecutableTrustStore = .shared) throws {
        guard machine == "virt-9.2" else { throw VMBackendTrustError.unsupportedMachine(machine) }
        let qemuIdentity = try VMBackendExecutableTrustStore.inspect(kind: .qemu, path: executablePath)
        let swtpmIdentity = try VMBackendExecutableTrustStore.inspect(kind: .swtpm, path: swtpmPath)
        guard try trustStore.isApproved(qemuIdentity) else { throw VMBackendTrustError.approvalRequired(qemuIdentity.path) }
        guard try trustStore.isApproved(swtpmIdentity) else { throw VMBackendTrustError.approvalRequired(swtpmIdentity.path) }
        let qemuOutput = try VMBackendVersionProbe.output(path: qemuIdentity.path, arguments: ["--version"], name: "QEMU")
        _ = try VMBackendVersion.qemu(qemuOutput)
        let swtpmOutput = try VMBackendVersionProbe.output(path: swtpmIdentity.path, arguments: ["--version"], name: "swtpm")
        _ = try VMBackendVersion.swtpm(swtpmOutput)
        // Re-hash after version probes so replacement between approval check and
        // launch fails closed. VMQEMUService repeats this immediately before run.
        guard try VMBackendExecutableTrustStore.inspect(kind: .qemu, path: executablePath) == qemuIdentity,
              try VMBackendExecutableTrustStore.inspect(kind: .swtpm, path: swtpmPath) == swtpmIdentity else {
            throw VMBackendTrustError.changedDuringInspection(executablePath)
        }
    }

    func verifyApprovedExecutables(using trustStore: VMBackendExecutableTrustStore = .shared) throws {
        try trustStore.verifyCurrentApproval(kind: .qemu, path: executablePath)
        try trustStore.verifyCurrentApproval(kind: .swtpm, path: swtpmPath)
    }

    func firmware(named name: String, overridePath: String = "") throws -> URL {
        let executable = URL(fileURLWithPath: executablePath).resolvingSymlinksInPath()
        let candidates = overridePath.isEmpty ? [
            executable.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("share/qemu/\(name)").path,
            "/opt/homebrew/share/qemu/\(name)", "/usr/local/share/qemu/\(name)"
        ] : [overridePath]
        guard let candidate = candidates.first(where: {
            $0.hasPrefix("/") && (try? URL(fileURLWithPath: $0).resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
        }) else { throw VMGuestError.missingTool(name) }
        return URL(fileURLWithPath: candidate)
    }
}
