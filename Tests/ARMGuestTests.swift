import Foundation
import Virtualization

@main
struct ARMGuestTests {
    @MainActor
    static func main() async throws {
        var count = 0
        func check(_ result: @autoclosure () -> Bool, _ message: String) {
            precondition(result(), "FAILED: \(message)"); count += 1
        }
        func rejects(_ operation: () throws -> Void, _ message: String) {
            do { try operation(); fatalError("Expected rejection: \(message)") } catch { count += 1 }
        }
        let fm = FileManager.default
        let testRoot = ProcessInfo.processInfo.environment["VOLUMEBOOT_ARM_TEST_ROOT"] ?? "/private/tmp"
        let scratch = URL(fileURLWithPath: testRoot).appendingPathComponent("VB-ARM-\(UUID())")
        try fm.createDirectory(at: scratch, withIntermediateDirectories: false)
        defer { try? fm.removeItem(at: scratch) }
        // Synthetic media validates host configuration; it is never claimed to contain an OS.
        let iso = scratch.appendingPathComponent("arm64.iso")
        try Data(repeating: 0, count: 4096).write(to: iso)
        rejects({ try VMGuestMedia.verifyISO(scratch.appendingPathComponent("missing.iso")) }, "missing ISO")
        rejects({ try VMGuestMedia.verifyISO(scratch) }, "directory is not an ISO")
        let legacy = ManagedVMManifest(version: 2, id: UUID(), createdAt: Date(), diskSizeGiB: 64, state: .installed, lastFailure: nil)
        var legacyObject = try JSONSerialization.jsonObject(with: JSONEncoder().encode(legacy)) as! [String: Any]
        legacyObject.removeValue(forKey: "guestOS")
        let decoded = try JSONDecoder().decode(ManagedVMManifest.self, from: JSONSerialization.data(withJSONObject: legacyObject))
        check(decoded.guestOS == .macOS, "old macOS manifest compatibility")
        var hardware = VMHardwareSettings.default
        hardware.audioOutputEnabled = false
        let linux = scratch.appendingPathComponent("Linux")
        let runtime = VMRuntimeService()
        try runtime.createARMGuest(at: linux, guestOS: .linuxARM, installationMediaURL: iso, diskSizeGiB: 64,
                                   connectivity: .default, hardware: hardware)
        let linuxRecord = try VMRegistry.read(at: linux)
        check(linuxRecord.guestOS == .linuxARM && linuxRecord.state == .installing, "Linux installation state")
        check(fm.fileExists(atPath: linux.appendingPathComponent("efi-vars.bin").path), "Linux persistent EFI variables")
        let identity = try Data(contentsOf: linux.appendingPathComponent("machine-id.bin"))
        check(VZGenericMachineIdentifier(dataRepresentation: identity) != nil, "valid Linux platform identity")
        try await runtime.startExistingVM(at: linux)
        check(runtime.virtualMachine?.state == .running, "native Linux EFI VM starts")
        rejects({ try runtime.finishARMInstallation(at: linux) }, "cannot eject installer while running")
        rejects({ try VMDiskImageStore.grow(at: hardware.bootDiskURL(in: linux), toGiB: 80) }, "live Linux disk locked")
        try await runtime.stop()
        check(!runtime.hasSession, "native Linux shutdown")
        rejects({ try runtime.createARMGuest(at: linux, guestOS: .linuxARM, installationMediaURL: iso, diskSizeGiB: 64,
                                             connectivity: .default, hardware: hardware) }, "existing bundle untouched")
        try runtime.finishARMInstallation(at: linux)
        var installedLinux = try VMRegistry.read(at: linux)
        check(installedLinux.state == .installed, "explicit Linux completion")
        rejects({ try runtime.finishARMInstallation(at: linux) }, "no implicit repeat completion")
        installedLinux.installationMediaPath = scratch.appendingPathComponent("removed-installer.iso").path
        try VMRegistry.write(installedLinux, at: linux)
        try await runtime.startExistingVM(at: linux)
        check(runtime.virtualMachine?.state == .running, "installed Linux boots after installer media is removed")
        try await runtime.stop()
        let tools = try VMQEMUSettings.discover()
        let windows = scratch.appendingPathComponent("Windows with spaces,comma")
        try runtime.createARMGuest(at: windows, guestOS: .windowsARM, installationMediaURL: iso, diskSizeGiB: 64,
            connectivity: .default, hardware: hardware, qemuSettings: tools,
            firmwareCodeURL: tools.firmware(named: "edk2-aarch64-code.fd"),
            firmwareVariablesURL: tools.firmware(named: "edk2-arm-vars.fd"))
        var windowsRecord = try VMRegistry.read(at: windows)
        check(windowsRecord.guestOS == .windowsARM && windowsRecord.state == .installing, "Windows installation state")
        let secondary = scratch.appendingPathComponent("Read only,secondary.img")
        try VMDiskImageStore.create(at: secondary, sizeGiB: 1)
        hardware.additionalDisks = [VMAdditionalDisk(path: secondary.path, readOnly: true)]
        try VMHardwareStore.save(hardware, to: windows)
        let args = try VMQEMUPlan.arguments(folder: windows, record: windowsRecord, hardware: hardware,
            connectivity: .default, tpmSocket: scratch.appendingPathComponent("tpm.sock"), accelerator: "tcg", display: "none")
        check(args.contains("Windows with spaces,,comma"), "QEMU name escapes commas")
        check(args.contains(where: { $0.contains("highmem=on") }), "Windows supports four or more GiB of RAM")
        check(args.contains("tpm-tis-device,tpmdev=tpm0"), "TPM 2.0 device")
        check(args.contains("nvme,drive=bootdisk,serial=VolumeBootMain,bootindex=1"), "Windows inbox NVMe disk")
        check(args.contains(where: { $0.contains("drive=installer") }), "install media attached")
        let blocks = args.enumerated().compactMap { index, value -> [String: Any]? in
            guard index > 0, args[index - 1] == "-blockdev" else { return nil }
            return (try? JSONSerialization.jsonObject(with: Data(value.utf8))) as? [String: Any]
        }
        check(blocks.contains { ($0["file"] as? [String: Any])?["filename"] as? String == windows.appendingPathComponent("disk.img").path }, "structured paths preserve spaces and commas")
        var unsupported = VMConnectivitySettings.default
        unsupported.guestToolsEnabled = true
        rejects({ _ = try VMQEMUPlan.arguments(folder: windows, record: windowsRecord, hardware: hardware,
            connectivity: unsupported, tpmSocket: scratch.appendingPathComponent("tpm.sock")) }, "unsupported Windows sharing rejected")
        // Start the actual installed QEMU + swtpm headlessly with TCG, then exercise QMP shutdown.
        let service = VMQEMUService()
        let bootURL = hardware.bootDiskURL(in: windows)
        try await service.start(folder: windows, record: windowsRecord, hardware: hardware, connectivity: .default,
            leases: [try VMDiskImageLease(url: bootURL, writable: true), try VMDiskImageLease(url: secondary)], accelerator: "tcg", display: "none")
        check(service.isRunning, "live QEMU and TPM startup")
        rejects({ try VMDiskImageStore.grow(at: bootURL, toGiB: 80) }, "live Windows session locks its disk")
        try await service.stop()
        check(!service.isRunning, "QMP stop cleans session")
        let unlocked = try VMDiskImageStore.grow(at: bootURL, toGiB: 80)
        check(unlocked.sizeGiB == 80, "Windows stop releases disk lock")
        try runtime.finishARMInstallation(at: windows)
        windowsRecord = try VMRegistry.read(at: windows)
        try await service.start(folder: windows, record: windowsRecord, hardware: hardware, connectivity: .default,
            leases: [try VMDiskImageLease(url: bootURL, writable: true), try VMDiskImageLease(url: secondary)], display: "none")
        check(service.isRunning, "live Windows backend uses HVF acceleration")
        let stopTask = Task { @MainActor in try await service.stop() }
        stopTask.cancel()
        try await stopTask.value
        check(!service.isRunning, "cancelled caller still completes Windows shutdown")
        let released = try VMDiskImageLease(url: bootURL, writable: true)
        check(released.info.sizeGiB == 80, "cancelled stop releases locks after shutdown")
        let bootArgs = try VMQEMUPlan.arguments(folder: windows, record: windowsRecord, hardware: hardware,
            connectivity: .default, tpmSocket: scratch.appendingPathComponent("tpm.sock"))
        check(!bootArgs.contains(where: { $0.contains("drive=installer") }), "completed install ejects ISO")
        check(bootArgs.contains("host") && bootArgs.contains("hvf"), "normal Windows boots use Apple acceleration")
        print("PASS: \(count) ARM guest metadata, installation state, QEMU configuration, live TPM/start/stop, and ISO ejection assertions")
    }
}
