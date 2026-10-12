import Foundation

/// File and policy checks are separate from the final backend configuration validation.
enum VMReadiness {
    static func issues(folder: URL, record: ManagedVMManifest, hardware: VMHardwareSettings,
                       connectivity: VMConnectivitySettings, interfaces: Set<String>,
                       cpuRange: ClosedRange<Int> = 2...64, maximumMemoryGiB: Int = 1024) -> [String] {
        var issues: [String] = []
        func check(_ operation: () throws -> Void) {
            do { try operation() } catch { issues.append(error.localizedDescription) }
        }
        check { try VMHardwarePolicy.verify(hardware, vmFolder: folder, cpuRange: cpuRange, maximumMemoryGiB: maximumMemoryGiB) }
        check { try VMConnectivityPolicy.verify(connectivity, vmFolder: folder, validInterfaces: interfaces) }
        check { _ = try VMDiskImageStore.inspect(at: hardware.bootDiskURL(in: folder)) }
        if record.state != .installed && !(record.guestOS != .macOS && record.state == .installing) {
            issues.append("This VM has an incomplete or failed provisioning record. Create a new workspace; retain the original for diagnosis.")
        }
        let names: [String]
        switch record.guestOS {
        case .macOS: names = ["hardware-model.bin", "machine-id.bin", "auxiliary-storage"]
        case .linuxARM: names = ["machine-id.bin", "efi-vars.bin"]
        case .windowsARM: names = ["firmware-code.fd", "firmware-vars.fd"]
        }
        for name in names {
            if (try? folder.appendingPathComponent(name).resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) != true {
                issues.append("Missing VM identity or firmware file: \(name)")
            }
        }
        if record.state == .installing {
            check {
                guard let path = record.installationMediaPath else { throw VMGuestError.invalidISO }
                try VMGuestMedia.verifyISO(URL(fileURLWithPath: path))
            }
        }
        if record.guestOS == .windowsARM {
            check {
                guard let tools = record.qemu else { throw VMGuestError.missingTool("saved QEMU settings") }
                let discovered = try VMQEMUSettings.discover(qemuPath: tools.executablePath, swtpmPath: tools.swtpmPath)
                if let unapproved = try discovered.firstUnapprovedExecutable() {
                    issues.append("Approval required for \(unapproved.kind.rawValue) at \(unapproved.path)")
                }
                guard connectivity.networkMode != .bridged, connectivity.sharedFolderPath == nil,
                      !connectivity.guestToolsEnabled, !hardware.microphoneEnabled else { throw VMGuestError.unsupportedWindowsSettings }
                if let path = record.driverMediaPath { try VMGuestMedia.verifyISO(URL(fileURLWithPath: path)) }
            }
        }
        return Array(NSOrderedSet(array: issues)) as? [String] ?? issues
    }
}
