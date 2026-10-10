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
        let storage = scratch.appendingPathComponent("Storage.raw")
        model.createDiskImage(at: storage, sizeGiB: 1, asBootDisk: false)
        check(fm.fileExists(atPath: storage.path), "create workflow produces image")
        let attached = try VMHardwareStore.load(from: bundle)
        check(attached.additionalDisks.first?.path == storage.path, "attachment persisted")
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
        model.attachDisposableDisk = true
        model.loadHardwareProfile(for: bundle)
        check(!model.attachDisposableDisk, "loading Windows clears unsupported physical attachment")
        model.installationISOPath = iso.path
        model.windowsDriverISOPath = ""
        model.saveARMGuestMedia()
        let savedMedia = try VMRegistry.read(at: bundle)
        check(savedMedia.installationMediaPath == iso.path && savedMedia.driverMediaPath == nil, "replacement installer and driver detachment persist")
        model.installationISOPath = ""
        model.saveARMGuestMedia()
        let rejectedMedia = try VMRegistry.read(at: bundle)
        check(rejectedMedia.installationMediaPath == iso.path, "incomplete installation keeps installer on invalid media update")
        print("PASS: \(count) app disk workflow, persisted selection, manifest, and failed startup assertions")
    }
}
