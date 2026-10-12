import Foundation

@main
struct AppDiskWorkflowTests {
    @MainActor
    static func main() async throws {
        var count = 0
        func check(_ result: @autoclosure () -> Bool, _ message: String) {
            precondition(result(), "FAILED: \(message)")
            count += 1
        }
        let fm = FileManager.default
        let scratch = fm.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("VB-Workflow-\(UUID())")
        try fm.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: scratch) }
        let bundle = scratch.appendingPathComponent("MacVM")
        try fm.createDirectory(at: bundle, withIntermediateDirectories: false)
        let bundledDisk = bundle.appendingPathComponent("disk.img")
        try VMDiskImageStore.create(at: bundledDisk, sizeGiB: 64)
        try VMHardwareStore.save(.default, to: bundle)
        try VMRegistry.write(ManagedVMManifest(version: 2, id: UUID(), createdAt: Date(), diskSizeGiB: 64,
                                              state: .installed, lastFailure: nil), at: bundle)
        let model = AppModel()
        model.loadHardwareProfile(for: bundle)
        let alias = scratch.appendingPathComponent("VM shortcut")
        try fm.createSymbolicLink(at: alias, withDestinationURL: bundle)
        model.loadHardwareProfile(for: alias)
        check(model.vmFolderPath == bundle.path, "workspace aliases use the canonical folder")
        check(model.knownVMs.filter { $0.url.path == bundle.path }.count == 1, "library deduplicates filesystem aliases")
        let storage = scratch.appendingPathComponent("Storage.raw")
        model.createDiskImage(at: storage, sizeGiB: 1, asBootDisk: false)
        check(fm.fileExists(atPath: storage.path), "create workflow produces image")
        let attached = try VMHardwareStore.load(from: bundle)
        check(attached.additionalDisks.first?.path == storage.path, "attachment persisted")
        check(!model.hasUnsavedHardware, "automatic disk attachment keeps saved baseline in sync")
        model.setDiskReadOnly(model.hardware.additionalDisks[0], true)
        let readOnly = try VMHardwareStore.load(from: bundle)
        check(readOnly.additionalDisks[0].readOnly && !model.hasUnsavedHardware, "read-only access persists without dirty hardware")
        try Data("stable-machine-identity".utf8).write(to: bundle.appendingPathComponent("machine-id.bin"))
        try Data("firmware-state".utf8).write(to: bundle.appendingPathComponent("efi-vars.bin"))
        try fm.createDirectory(at: bundle.appendingPathComponent("tpm"), withIntermediateDirectories: true)
        try Data("persistent-tpm-state".utf8).write(to: bundle.appendingPathComponent("tpm/state.bin"))
        let backup = scratch.appendingPathComponent("MacVM-backup")
        try VMBackupService.create(from: bundle, to: backup)
        let restored = scratch.appendingPathComponent("Restored MacVM")
        try VMBackupService.restore(from: backup, to: restored)
        let restoredHardware = try VMHardwareStore.load(from: restored)
        check(fm.fileExists(atPath: restored.appendingPathComponent("machine-id.bin").path), "backup preserves machine identity")
        check(fm.fileExists(atPath: restored.appendingPathComponent("efi-vars.bin").path) && fm.fileExists(atPath: restored.appendingPathComponent("tpm/state.bin").path), "backup preserves firmware and TPM state")
        check(restoredHardware.additionalDisks.count == 1 && fm.fileExists(atPath: restoredHardware.additionalDisks[0].path), "restore recreates external disk images")
        check(restoredHardware.additionalDisks[0].path != storage.path, "restore rewrites external disk paths")
        var transactionHardware = restoredHardware
        transactionHardware.displayName = "transactional update"
        var transactionConnectivity = try VMConnectivityStore.load(from: restored)
        transactionConnectivity.guestToolsEnabled = true
        try VMWorkspaceTransaction.commit(at: restored, manifest: try VMRegistry.read(at: restored),
            hardware: transactionHardware, connectivity: transactionConnectivity)
        let coordinatedHardware = try VMHardwareStore.load(from: restored)
        let coordinatedConnectivity = try VMConnectivityStore.load(from: restored)
        check(coordinatedHardware.displayName == "transactional update" && coordinatedConnectivity.guestToolsEnabled,
              "coordinated workspace update commits all profiles")
        let previousBackupHardware = try Data(contentsOf: restored.appendingPathComponent(VMHardwareStore.filename))
        let interrupted: [String: Any] = ["phase": "prepared", "files": [["name": VMHardwareStore.filename, "previous": previousBackupHardware.base64EncodedString()]]]
        try JSONSerialization.data(withJSONObject: interrupted).write(to: restored.appendingPathComponent(".workspace-transaction.json"), options: .atomic)
        transactionHardware.displayName = "interrupted update"
        try VMHardwareStore.save(transactionHardware, to: restored)
        _ = try VMRegistry.read(at: restored)
        let recoveredHardware = try VMHardwareStore.load(from: restored)
        check(recoveredHardware.displayName == "transactional update" &&
              !fm.fileExists(atPath: restored.appendingPathComponent(".workspace-transaction.json").path), "interrupted workspace update recovers previous generation")
        let previousFolder = model.vmFolderPath
        let previousModelHardware = model.hardware
        model.loadHardwareProfile(for: scratch.appendingPathComponent("does-not-exist"))
        check(model.vmFolderPath == previousFolder && model.hardware == previousModelHardware, "failed profile load preserves current selection")
        let invalid = scratch.appendingPathComponent("Broken profile")
        try fm.createDirectory(at: invalid, withIntermediateDirectories: false)
        let invalidRecord = try VMRegistry.read(at: bundle)
        try VMRegistry.write(invalidRecord, at: invalid)
        var differentHardware = VMHardwareSettings.default
        differentHardware.displayName = "Must not replace the current profile"
        try VMHardwareStore.save(differentHardware, to: invalid)
        try Data("invalid JSON".utf8).write(to: invalid.appendingPathComponent("connectivity.json"))
        model.loadHardwareProfile(for: invalid)
        check(model.vmFolderPath == previousFolder && model.hardware == previousModelHardware, "connectivity load failure cannot partially replace selection")
        let futureRecord = ManagedVMManifest(version: 99, id: UUID(), createdAt: Date(), diskSizeGiB: 64,
            state: .installed, lastFailure: nil)
        try VMRegistry.write(futureRecord, at: invalid)
        do { _ = try VMRegistry.read(at: invalid); fatalError("Expected future manifest rejection") }
        catch { check(error.localizedDescription.contains("unsupported"), "future manifest rejected with recovery guidance") }
        model.hardware.cpuCount += 1
        check(model.hasUnsavedHardware && !model.canStartVM, "unsaved hardware blocks a misleading start")
        await model.bootManagedVM()
        check(model.vmStatus.contains("Save or reload"), "start never silently discards edits")
        model.loadHardwareProfile(for: bundle)
        check(!model.hasUnsavedChanges, "reload restores saved baseline")
        differentHardware.cpuCount = 4
        let readiness = VMReadiness.issues(folder: bundle, record: try VMRegistry.read(at: bundle), hardware: differentHardware,
            connectivity: .default, interfaces: [], cpuRange: 2...2, maximumMemoryGiB: 4)
        check(readiness.contains(VMHardwareError.invalidCPU.localizedDescription), "readiness respects host CPU limits")
        do {
            let activeLease = try VMDiskImageLease(url: storage)
            model.deleteDiskImage(at: storage)
            let stillAttached = try VMHardwareStore.load(from: bundle)
            check(fm.fileExists(atPath: storage.path) && !stillAttached.additionalDisks.isEmpty, "locked deletion preserves file and profile")
            withExtendedLifetime(activeLease) {}
        }
        model.detachDiskImage(model.hardware.additionalDisks[0])
        check(fm.fileExists(atPath: storage.path), "detach keeps file")
        let detached = try VMHardwareStore.load(from: bundle)
        check(detached.additionalDisks.isEmpty, "detach persisted")
        let externalBoot = scratch.appendingPathComponent("macOS.img")
        model.createDiskImage(at: externalBoot, sizeGiB: 64, asBootDisk: true)
        let selected = try VMHardwareStore.load(from: bundle)
        check(selected.bootDiskPath == externalBoot.path, "external boot target persisted")
        model.growDiskImage(at: externalBoot, toGiB: 80)
        let grown = try VMDiskImageStore.inspect(at: externalBoot)
        let manifest = try VMRegistry.read(at: bundle)
        check(grown.sizeBytes == 80 * VMDiskImageStore.gibibyte && manifest.diskSizeGiB == 80, "resize updates image and manifest")
        model.deleteDiskImage(at: externalBoot)
        check(!fm.fileExists(atPath: externalBoot.path), "boot image deletion")
        check(model.hardware.bootDiskPath == externalBoot.path, "missing boot target retained")
        check(model.diskImageStatus.contains("replacement"), "boot deletion reports next action accurately")
        model.useBundleBootDisk()
        let reset = try VMHardwareStore.load(from: bundle)
        check(reset.bootDiskPath == nil, "legacy boot target restored")
        model.selectDiskImage(storage, asBootDisk: true)
        check(model.hardware.bootDiskPath == nil, "undersized boot image rejected without changing selection")
        model.selectDiskImage(storage, asBootDisk: false)
        model.deleteDiskImage(at: storage)
        let deleted = try VMHardwareStore.load(from: bundle)
        check(deleted.additionalDisks.isEmpty && !fm.fileExists(atPath: storage.path), "secondary deletion removes saved attachment")
        model.selectDiskImage(bundledDisk, asBootDisk: true)
        check(model.hardware.bootDiskPath == nil, "loading bundle image preserves default path")
        do {
            try await model.vm.startExistingVM(at: bundle)
            fatalError("Expected missing virtual Mac identity")
        } catch {
            check(model.vm.virtualMachine == nil && !model.vm.operationInProgress, "failed startup clears busy state")
        }
        let lease = try VMDiskImageLease(url: bundledDisk)
        check(lease.info.sizeBytes == 64 * VMDiskImageStore.gibibyte, "failed startup releases image lock")
        withExtendedLifetime(lease) {}
        let iso = scratch.appendingPathComponent("replacement.iso")
        try Data(repeating: 0, count: 4096).write(to: iso)
        var armRecord = try VMRegistry.read(at: bundle)
        armRecord.guestOS = .windowsARM
        armRecord.state = .installing
        armRecord.installationMediaPath = scratch.appendingPathComponent("moved.iso").path
        armRecord.driverMediaPath = iso.path
        armRecord.qemu = VMQEMUSettings(executablePath: "/usr/bin/true", swtpmPath: "/usr/bin/true")
        try VMRegistry.write(armRecord, at: bundle)
        model.loadHardwareProfile(for: bundle)
        model.installationISOPath = iso.path
        model.windowsDriverISOPath = ""
        model.saveARMGuestMedia()
        let savedMedia = try VMRegistry.read(at: bundle)
        check(savedMedia.installationMediaPath == iso.path && savedMedia.driverMediaPath == nil, "replacement installer and driver detachment persist")
        model.installationISOPath = ""
        model.saveARMGuestMedia()
        let rejectedMedia = try VMRegistry.read(at: bundle)
        check(rejectedMedia.installationMediaPath == iso.path, "incomplete installation keeps installer on invalid media update")
        model.loadHardwareProfile(for: bundle)
        let savedGuest = model.guestOS
        model.selectNewGuest(.macOS)
        check(model.guestOS == savedGuest, "existing guest type is immutable in setup selector")
        model.validateVMConfiguration()
        check(!model.validationIssues.isEmpty, "readiness detects missing identity and firmware")
        let preferences = MemoryVMPreferences()
        let remembered = AppModel(preferences: preferences)
        remembered.loadHardwareProfile(for: bundle)
        let reopened = AppModel(preferences: preferences)
        check(reopened.vmFolderPath == bundle.path && !reopened.knownVMs.isEmpty, "recent workspace survives model restart")
        preferences.values.removeAll()
        model.beginNewVM()
        check(model.currentManifest == nil && model.vmFolderPath.isEmpty && model.hardware == .default && model.connectivity == .default,
              "new workspace resets previous resources and media")
        check(!model.hasUnsavedChanges, "empty new workspace has no discard warning")
        model.restoreImagePath = iso.path
        check(model.hasUnsavedChanges && model.currentManifest == nil, "configured draft participates in discard protection")
        model.beginNewVM()
        check(!model.hasUnsavedChanges, "discarding draft restores clean configuration")
        print("PASS: \(count) app disk workflow, persisted selection, manifest, and failed startup assertions")
    }
}

private final class MemoryVMPreferences: VMPreferences {
    var values: [String: Any] = [:]
    func stringArray(forKey key: String) -> [String]? { values[key] as? [String] }
    func set(_ value: Any?, forKey key: String) { values[key] = value }
}
