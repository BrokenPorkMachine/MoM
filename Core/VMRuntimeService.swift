import Foundation
import Virtualization

@MainActor
final class VMRuntimeService: NSObject, @preconcurrency VZVirtualMachineDelegate {
    enum RuntimeError: LocalizedError {
        case unsupportedHost, missingMetadata(String), invalidMetadata(String), noVM, busy, incompleteInstallation, unsafeDestination
        var errorDescription: String? {
            switch self {
            case .unsupportedHost: return "Managed ARM guests require an Apple Silicon host"
            case .missingMetadata(let name): return "Missing VM file: \(name)"
            case .invalidMetadata(let name): return "Invalid VM metadata: \(name)"
            case .noVM: return "No running VM"
            case .busy: return "VM runtime is already in use"
            case .incompleteInstallation: return "VM installation is incomplete; inspect the manifest before retrying"
            case .unsafeDestination: return "VM destination cannot be a device node or an existing path"
            }
        }
    }
    private(set) var virtualMachine: VZVirtualMachine?
    #if arch(arm64)
    private(set) var installer: VZMacOSInstaller?
    #else
    private var installer: AnyObject?
    #endif
    var installationProgress: Double { installer?.progress.fractionCompleted ?? 0 }
    private(set) var currentFolder: URL?
    private var workspaceLease: VMWorkspaceLease?
    private var imageLeases: [VMDiskImageLease] = []
    private(set) var operationInProgress = false
    private let qemu = VMQEMUService()
    var onExternalStateChange: ((String) -> Void)?
    var hasSession: Bool { virtualMachine != nil || qemu.isRunning }
    var usesExternalConsole: Bool { qemu.isRunning }
    var externalConsoleProcessID: Int32? { qemu.processIdentifier }

    override init() {
        super.init()
        qemu.onExit = { [weak self] status in
            self?.currentFolder = nil
            self?.workspaceLease = nil
            self?.onExternalStateChange?(status)
        }
    }

    func guestDidStop(_ virtualMachine: VZVirtualMachine) {
        completeNativeSession(virtualMachine, message: "Guest shut down; disk images released")
    }

    func virtualMachine(_ virtualMachine: VZVirtualMachine, didStopWithError error: Error) {
        completeNativeSession(virtualMachine, message: "Guest stopped with an error: \(error.localizedDescription)")
    }

    private func completeNativeSession(_ ended: VZVirtualMachine, message: String) {
        guard virtualMachine === ended, installer == nil, !operationInProgress else { return }
        virtualMachine = nil; currentFolder = nil; imageLeases = []; workspaceLease = nil
        onExternalStateChange?(message)
    }

    func requestShutdown() throws {
        if qemu.isRunning { try qemu.requestShutdown(); return }
        guard let virtualMachine, virtualMachine.canRequestStop else { throw RuntimeError.noVM }
        try virtualMachine.requestStop()
    }

    func startExistingVM(at folder: URL) async throws {
        Diagnostics.record("VM start requested", category: "startup")
        #if arch(arm64)
        guard !hasSession, !operationInProgress else { throw RuntimeError.busy }
        operationInProgress = true
        defer { operationInProgress = false }
        let lease = try VMWorkspaceLease(folder: folder)
        workspaceLease = lease
        var keepLease = false
        defer { if !keepLease { workspaceLease = nil } }
        let manifest = try VMRegistry.read(at: folder)
        guard manifest.state == .installed || (manifest.guestOS != .macOS && manifest.state == .installing) else {
            throw RuntimeError.incompleteInstallation
        }
        let connectivity = try VMConnectivityStore.load(from: folder)
        if connectivity.guestToolsEnabled { try HostGuestExchange.createIfNeeded(in: folder) }
        let hardware = try VMHardwareStore.load(from: folder)
        let managedPolicy = try VMManagedPolicy.load()
        try managedPolicy.verifyHardware(hardware)
        try VMConnectivityPolicy.verifyManaged(connectivity, hardware: hardware, policy: managedPolicy, vmFolder: folder)
        try VMHardwarePolicy.verify(hardware, vmFolder: folder,
            cpuRange: VZVirtualMachineConfiguration.minimumAllowedCPUCount...VZVirtualMachineConfiguration.maximumAllowedCPUCount,
            maximumMemoryGiB: Int(VZVirtualMachineConfiguration.maximumAllowedMemorySize / 1_073_741_824))
        let leases = try lockImages(folder: folder, hardware: hardware)
        if manifest.guestOS == .windowsARM {
            currentFolder = folder
            do { try await qemu.start(folder: folder, record: manifest, hardware: hardware, connectivity: connectivity, leases: leases) }
            catch { currentFolder = nil; workspaceLease = nil; throw error }
            keepLease = true
            return
        }
        let config = try makeConfiguration(folder: folder, hardware: hardware)
        let vm = VZVirtualMachine(configuration: config)
        vm.delegate = self
        virtualMachine = vm
        currentFolder = folder
        imageLeases = leases
        do { try await vm.start() } catch {
            virtualMachine = nil; currentFolder = nil; imageLeases = []; workspaceLease = nil; throw error
        }
        keepLease = true
        #else
        throw RuntimeError.unsupportedHost
        #endif
    }

    /// A guest can stop on its own; permit safe lease cleanup without invoking
    /// `stop()` a second time on an already stopped VM.
    func discardAlreadyStoppedSession() -> Bool {
        if qemu.isRunning { return false }
        guard let vm = virtualMachine else { return true }
        guard vm.state == .stopped || vm.state == .error else { return false }
        virtualMachine = nil
        currentFolder = nil
        imageLeases = []
        workspaceLease = nil
        return true
    }

    func stop() async throws {
        Diagnostics.record("VM stop requested", category: "shutdown")
        guard !operationInProgress else { throw RuntimeError.busy }
        operationInProgress = true
        defer { operationInProgress = false }
        if qemu.isRunning {
            try await qemu.stop()
            currentFolder = nil
            workspaceLease = nil
            return
        }
        guard let virtualMachine else { throw RuntimeError.noVM }
        try await virtualMachine.stop()
        self.virtualMachine = nil
        currentFolder = nil
        imageLeases = []
        workspaceLease = nil
    }
    #if arch(arm64)
    private func lockImages(folder: URL, hardware: VMHardwareSettings) throws -> [VMDiskImageLease] {
        var leases = [try VMDiskImageLease(url: hardware.bootDiskURL(in: folder), writable: true)]
        for disk in hardware.additionalDisks {
            leases.append(try VMDiskImageLease(url: URL(fileURLWithPath: disk.path), writable: !disk.readOnly))
        }
        return leases
    }

    private func makeConfiguration(folder: URL, hardware: VMHardwareSettings) throws -> VZVirtualMachineConfiguration {
        func file(_ name: String) throws -> URL {
            let url = folder.appendingPathComponent(name)
            guard FileManager.default.fileExists(atPath: url.path) else { throw RuntimeError.missingMetadata(name) }
            return url
        }
        let record = try VMRegistry.read(at: folder)
        let config = VZVirtualMachineConfiguration()
        if record.guestOS == .macOS {
            guard let model = VZMacHardwareModel(dataRepresentation: try Data(contentsOf: file("hardware-model.bin"))), model.isSupported else {
                throw RuntimeError.invalidMetadata("hardware-model.bin")
            }
            guard let identity = VZMacMachineIdentifier(dataRepresentation: try Data(contentsOf: file("machine-id.bin"))) else {
                throw RuntimeError.invalidMetadata("machine-id.bin")
            }
            let platform = VZMacPlatformConfiguration()
            platform.hardwareModel = model
            platform.machineIdentifier = identity
            platform.auxiliaryStorage = VZMacAuxiliaryStorage(url: try file("auxiliary-storage"))
            config.platform = platform
            config.bootLoader = VZMacOSBootLoader()
        } else {
            let platform = VZGenericPlatformConfiguration()
            guard let identity = VZGenericMachineIdentifier(dataRepresentation: try Data(contentsOf: file("machine-id.bin"))) else {
                throw RuntimeError.invalidMetadata("machine-id.bin")
            }
            platform.machineIdentifier = identity
            config.platform = platform
            let boot = VZEFIBootLoader()
            boot.variableStore = VZEFIVariableStore(url: try file("efi-vars.bin"))
            config.bootLoader = boot
        }
        config.cpuCount = hardware.cpuCount
        config.memorySize = UInt64(hardware.memoryGiB) * 1_073_741_824
        let attachment = try VZDiskImageStorageDeviceAttachment(url: hardware.bootDiskURL(in: folder), readOnly: false)
        config.storageDevices = [VZVirtioBlockDeviceConfiguration(attachment: attachment)]
        for disk in hardware.additionalDisks {
            let image = try VZDiskImageStorageDeviceAttachment(url: URL(fileURLWithPath: disk.path), readOnly: disk.readOnly)
            config.storageDevices.append(VZVirtioBlockDeviceConfiguration(attachment: image))
        }
        if record.guestOS == .linuxARM, record.state == .installing {
            guard let path = record.installationMediaPath else { throw VMGuestError.invalidISO }
            let iso = URL(fileURLWithPath: path)
            try VMGuestMedia.verifyISO(iso)
            config.storageDevices.append(VZUSBMassStorageDeviceConfiguration(
                attachment: try VZDiskImageStorageDeviceAttachment(url: iso, readOnly: true)))
        }
        if record.guestOS == .macOS {
            let graphics = VZMacGraphicsDeviceConfiguration()
            graphics.displays = [VZMacGraphicsDisplayConfiguration(widthInPixels: hardware.display.width,
                heightInPixels: hardware.display.height, pixelsPerInch: hardware.display.pixelsPerInch)]
            config.graphicsDevices = [graphics]
            config.keyboards = [hardware.keyboard == .mac ? VZMacKeyboardConfiguration() : VZUSBKeyboardConfiguration()]
            config.pointingDevices = [hardware.pointer == .trackpad ? VZMacTrackpadConfiguration() : VZUSBScreenCoordinatePointingDeviceConfiguration()]
        } else {
            let graphics = VZVirtioGraphicsDeviceConfiguration()
            graphics.scanouts = [VZVirtioGraphicsScanoutConfiguration(widthInPixels: hardware.display.width, heightInPixels: hardware.display.height)]
            config.graphicsDevices = [graphics]
            config.keyboards = [VZUSBKeyboardConfiguration()]
            config.pointingDevices = [VZUSBScreenCoordinatePointingDeviceConfiguration()]
        }
        config.entropyDevices = [VZVirtioEntropyDeviceConfiguration()]
        if hardware.audioOutputEnabled {
            let sound = VZVirtioSoundDeviceConfiguration()
            let output = VZVirtioSoundDeviceOutputStreamConfiguration()
            output.sink = VZHostAudioOutputStreamSink()
            var streams: [VZVirtioSoundDeviceStreamConfiguration] = [output]
            if hardware.microphoneEnabled {
                let input = VZVirtioSoundDeviceInputStreamConfiguration()
                input.source = VZHostAudioInputStreamSource()
                streams.append(input)
            }
            sound.streams = streams
            config.audioDevices = [sound]
        }
        let connectivity = try VMConnectivityStore.load(from: folder)
        let interfaces = VZBridgedNetworkInterface.networkInterfaces
        try VMConnectivityPolicy.verify(connectivity, vmFolder: folder, validInterfaces: Set(interfaces.map(\.identifier)))
        if connectivity.networkMode != .disconnected {
            let network = VZVirtioNetworkDeviceConfiguration()
            let record = try VMRegistry.read(at: folder)
            guard let mac = VZMACAddress(string: VMConnectivityPolicy.stableMAC(for: record.id)) else {
                throw RuntimeError.invalidMetadata("network MAC address")
            }
            network.macAddress = mac
            switch connectivity.networkMode {
            case .nat:
                network.attachment = VZNATNetworkDeviceAttachment()
            case .bridged:
                guard let interface = interfaces.first(where: { $0.identifier == connectivity.bridgedInterfaceID }) else {
                    throw VMConnectivityError.invalidBridgedInterface
                }
                // Signing for bridged networking requires com.apple.vm.networking.
                network.attachment = VZBridgedNetworkDeviceAttachment(interface: interface)
            case .disconnected: break
            }
            config.networkDevices = [network]
        } else {
            config.networkDevices = []
        }

        if connectivity.sharedFolderPath != nil || connectivity.guestToolsEnabled {
            var directories: [String: VZSharedDirectory] = [:]
            if let path = connectivity.sharedFolderPath {
                directories["Workspace"] = VZSharedDirectory(url: URL(fileURLWithPath: path, isDirectory: true),
                                                              readOnly: connectivity.shareReadOnly)
            }
            if connectivity.guestToolsEnabled {
                let exchange = HostGuestExchange.root(for: folder)
                guard FileManager.default.fileExists(atPath: exchange.path) else {
                    throw RuntimeError.missingMetadata("Exchange directory")
                }
                directories["Exchange"] = VZSharedDirectory(url: exchange, readOnly: false)
            }
            let sharing = VZVirtioFileSystemDeviceConfiguration(tag: record.guestOS == .macOS ?
                VZVirtioFileSystemDeviceConfiguration.macOSGuestAutomountTag : "volumeboot")
            sharing.share = VZMultipleDirectoryShare(directories: directories)
            config.directorySharingDevices = [sharing]
        }
        try config.validate()
        return config
    }
    #endif

    /// ISO installers run interactively; completion is acknowledged after guest setup and shutdown.
    func createARMGuest(at folder: URL, guestOS: VMGuestOS, installationMediaURL: URL, diskSizeGiB: Int,
                        connectivity: VMConnectivitySettings, hardware: VMHardwareSettings,
                        qemuSettings: VMQEMUSettings? = nil, firmwareCodeURL: URL? = nil,
                        firmwareVariablesURL: URL? = nil, driverMediaURL: URL? = nil) throws {
        #if arch(arm64)
        guard !hasSession, !operationInProgress else { throw RuntimeError.busy }
        guard guestOS != .macOS else { throw VMGuestError.invalidState }
        operationInProgress = true
        defer { operationInProgress = false }
        let resolved = folder.standardizedFileURL.resolvingSymlinksInPath()
        guard folder.isFileURL, resolved.path != "/dev", !resolved.path.hasPrefix("/dev/"),
              resolved.path == folder.standardizedFileURL.path else { throw RuntimeError.unsafeDestination }
        guard !FileManager.default.fileExists(atPath: folder.path) else { throw ProvisioningError.destinationExists }
        try VMGuestMedia.verifyISO(installationMediaURL)
        if let driverMediaURL { try VMGuestMedia.verifyISO(driverMediaURL) }
        _ = try VMDiskImageStore.capacityBytes(diskSizeGiB, bootDisk: true)
        try VMHardwarePolicy.verify(hardware, vmFolder: folder,
            cpuRange: VZVirtualMachineConfiguration.minimumAllowedCPUCount...VZVirtualMachineConfiguration.maximumAllowedCPUCount,
            maximumMemoryGiB: Int(VZVirtualMachineConfiguration.maximumAllowedMemorySize / VMDiskImageStore.gibibyte))
        let managedPolicy = try VMManagedPolicy.load()
        try managedPolicy.verifyHardware(hardware)
        try VMConnectivityPolicy.verifyManaged(connectivity, hardware: hardware, policy: managedPolicy, vmFolder: folder)
        try VMConnectivityPolicy.verify(connectivity, vmFolder: folder,
            validInterfaces: Set(VZBridgedNetworkInterface.networkInterfaces.map(\.identifier)))
        if guestOS == .windowsARM {
            guard qemuSettings != nil, firmwareCodeURL != nil, firmwareVariablesURL != nil else {
                throw VMGuestError.missingTool("QEMU, swtpm, and AArch64 UEFI firmware")
            }
            guard connectivity.networkMode != .bridged, connectivity.sharedFolderPath == nil,
                  !connectivity.guestToolsEnabled, !hardware.microphoneEnabled else { throw VMGuestError.unsupportedWindowsSettings }
        }
        let suppliedDisk = try hardware.bootDiskPath.map { try VMDiskImageLease(url: URL(fileURLWithPath: $0), writable: true) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        let workspaceLease = try VMWorkspaceLease(folder: folder)
        var manifest = ManagedVMManifest(version: 3, id: UUID(), createdAt: Date(),
            diskSizeGiB: suppliedDisk.map { Int($0.info.sizeBytes / VMDiskImageStore.gibibyte) } ?? diskSizeGiB,
            state: .provisioning, lastFailure: nil, guestOS: guestOS, installationMediaPath: installationMediaURL.path,
            driverMediaPath: driverMediaURL?.path, qemu: qemuSettings)
        try VMRegistry.write(manifest, at: folder)
        do {
            try VMHardwareStore.save(hardware, to: folder)
            try VMConnectivityStore.save(connectivity, to: folder)
            if connectivity.guestToolsEnabled { try HostGuestExchange.createIfNeeded(in: folder) }
            if suppliedDisk == nil { try VMDiskImageStore.create(at: folder.appendingPathComponent("disk.img"), sizeGiB: diskSizeGiB) }
            if guestOS == .linuxARM {
                try VZGenericMachineIdentifier().dataRepresentation.write(to: folder.appendingPathComponent("machine-id.bin"), options: .atomic)
                _ = try VZEFIVariableStore(creatingVariableStoreAt: folder.appendingPathComponent("efi-vars.bin"), options: [])
            } else if let firmwareCodeURL, let firmwareVariablesURL {
                try FileManager.default.copyItem(at: firmwareCodeURL, to: folder.appendingPathComponent("firmware-code.fd"))
                try FileManager.default.copyItem(at: firmwareVariablesURL, to: folder.appendingPathComponent("firmware-vars.fd"))
            }
            manifest.state = .installing
            try VMRegistry.write(manifest, at: folder)
            if guestOS == .linuxARM { _ = try makeConfiguration(folder: folder, hardware: hardware) }
        } catch {
            manifest.state = .failed; manifest.lastFailure = error.localizedDescription
            try? VMRegistry.write(manifest, at: folder)
            throw error
        }
        withExtendedLifetime(workspaceLease) {}
        #else
        throw RuntimeError.unsupportedHost
        #endif
    }

    func finishARMInstallation(at folder: URL) throws {
        guard !hasSession, !operationInProgress else { throw RuntimeError.busy }
        let workspaceLease = try VMWorkspaceLease(folder: folder)
        defer { withExtendedLifetime(workspaceLease) {} }
        var manifest = try VMRegistry.read(at: folder)
        guard manifest.guestOS != .macOS, manifest.state == .installing else { throw VMGuestError.invalidState }
        let hardware = try VMHardwareStore.load(from: folder)
        try VMHardwarePolicy.verify(hardware, vmFolder: folder)
        _ = try VMDiskImageStore.inspect(at: hardware.bootDiskURL(in: folder))
        // An explicit user acknowledgement, not an inferred successful installation.
        manifest.state = .installed
        manifest.lastFailure = nil
        try VMRegistry.write(manifest, at: folder)
    }

    /// Creates a managed VM folder and installs macOS from an Apple IPSW restore image.
    /// Does not mount or modify physical storage devices. Incomplete folders are retained for investigation.
    func provision(at folder: URL, restoreImageURL: URL, diskSizeGiB: Int, connectivity: VMConnectivitySettings = .default,
                   hardware: VMHardwareSettings = .default) async throws {
        #if arch(arm64)
        guard !hasSession, !operationInProgress else { throw RuntimeError.busy }
        operationInProgress = true
        defer { operationInProgress = false }
        let resolvedFolder = folder.standardizedFileURL.resolvingSymlinksInPath()
        guard folder.isFileURL, resolvedFolder.path != "/dev", !resolvedFolder.path.hasPrefix("/dev/"),
              resolvedFolder.path == folder.standardizedFileURL.path, folder.lastPathComponent != "" else { throw RuntimeError.unsafeDestination }
        guard restoreImageURL.isFileURL, restoreImageURL.pathExtension.lowercased() == "ipsw" else {
            throw ProvisioningError.invalidRestoreImage
        }
        _ = try VMDiskImageStore.capacityBytes(diskSizeGiB, bootDisk: true)
        try VMHardwarePolicy.verify(hardware, vmFolder: folder,
            cpuRange: VZVirtualMachineConfiguration.minimumAllowedCPUCount...VZVirtualMachineConfiguration.maximumAllowedCPUCount,
            maximumMemoryGiB: Int(VZVirtualMachineConfiguration.maximumAllowedMemorySize / 1_073_741_824))
        // Lock a supplied installation target before awaiting restore-image inspection.
        let suppliedDisk = try hardware.bootDiskPath.map { try VMDiskImageLease(url: URL(fileURLWithPath: $0), writable: true) }
        try VMConnectivityPolicy.verify(connectivity, vmFolder: folder,
            validInterfaces: Set(VZBridgedNetworkInterface.networkInterfaces.map(\.identifier)))
        guard !FileManager.default.fileExists(atPath: folder.path) else { throw ProvisioningError.destinationExists }
        guard FileManager.default.fileExists(atPath: restoreImageURL.path) else { throw ProvisioningError.missingRestoreImage }

        let image = try await VZMacOSRestoreImage.image(from: restoreImageURL)
        guard let requirement = image.mostFeaturefulSupportedConfiguration else { throw ProvisioningError.noSupportedConfiguration }
        let model = requirement.hardwareModel
        guard model.isSupported else { throw ProvisioningError.noSupportedConfiguration }
        let memoryBytes = UInt64(hardware.memoryGiB) * 1_073_741_824
        guard hardware.cpuCount >= requirement.minimumSupportedCPUCount, memoryBytes >= requirement.minimumSupportedMemorySize else {
            throw ProvisioningError.insufficientResources
        }
        // Exclusive creation: never adopt or overwrite an existing folder.
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        let workspaceLease = try VMWorkspaceLease(folder: folder)
        let capacity = suppliedDisk.map { Int($0.info.sizeBytes / VMDiskImageStore.gibibyte) } ?? diskSizeGiB
        var manifest = ManagedVMManifest(version: 2, id: UUID(), createdAt: Date(), diskSizeGiB: capacity, state: .provisioning, lastFailure: nil)
        try VMRegistry.write(manifest, at: folder)
        do {
            try VMConnectivityStore.save(connectivity, to: folder)
            try VMHardwarePolicy.verify(hardware, vmFolder: folder,
                cpuRange: max(requirement.minimumSupportedCPUCount, VZVirtualMachineConfiguration.minimumAllowedCPUCount)...VZVirtualMachineConfiguration.maximumAllowedCPUCount,
                maximumMemoryGiB: Int(VZVirtualMachineConfiguration.maximumAllowedMemorySize / 1_073_741_824))
            try VMHardwareStore.save(hardware, to: folder)
            if connectivity.guestToolsEnabled { try HostGuestExchange.createIfNeeded(in: folder) }
            try model.dataRepresentation.write(to: folder.appendingPathComponent("hardware-model.bin"), options: .atomic)
            let identifier = VZMacMachineIdentifier()
            try identifier.dataRepresentation.write(to: folder.appendingPathComponent("machine-id.bin"), options: .atomic)
            _ = try VZMacAuxiliaryStorage(
                creatingStorageAt: folder.appendingPathComponent("auxiliary-storage"),
                hardwareModel: model,
                options: []
            )
            if suppliedDisk == nil {
                try VMDiskImageStore.create(at: folder.appendingPathComponent("disk.img"), sizeGiB: diskSizeGiB)
            }
            let bootLease = try suppliedDisk ?? VMDiskImageLease(url: hardware.bootDiskURL(in: folder), writable: true)
            var leases = [bootLease]
            for disk in hardware.additionalDisks {
                leases.append(try VMDiskImageLease(url: URL(fileURLWithPath: disk.path), writable: !disk.readOnly))
            }
            let config = try makeConfiguration(folder: folder, hardware: hardware)
            let vm = VZVirtualMachine(configuration: config)
            virtualMachine = vm
            currentFolder = folder
            imageLeases = leases
            let macInstaller = VZMacOSInstaller(virtualMachine: vm, restoringFromImageAt: restoreImageURL)
            installer = macInstaller
            defer { installer = nil; virtualMachine = nil; currentFolder = nil; imageLeases = [] }
            try await macInstaller.install()
            manifest.state = .installed
            try VMRegistry.write(manifest, at: folder)
        } catch {
            // Preserve incomplete installations and error provenance without destroying guest data.
            manifest.state = .failed
            manifest.lastFailure = String(describing: error)
            try? VMRegistry.write(manifest, at: folder)
            throw error
        }
        withExtendedLifetime(workspaceLease) {}
        #else
        throw RuntimeError.unsupportedHost
        #endif
    }
}

enum ProvisioningError: LocalizedError {
    case invalidRestoreImage, missingRestoreImage, invalidDiskSize, destinationExists
    case noSupportedConfiguration, insufficientResources, diskCreationFailed
    var errorDescription: String? {
        switch self {
        case .invalidRestoreImage: return "Select a local Apple macOS .ipsw restore image"
        case .missingRestoreImage: return "Restore image was not found"
        case .invalidDiskSize: return "Disk size must be between 64 and 2048 GiB"
        case .destinationExists: return "Destination already exists; choose a new empty VM folder path"
        case .noSupportedConfiguration: return "Restore image has no supported virtual Mac configuration on this host"
        case .insufficientResources: return "Requested CPUs or memory do not meet the restore image requirements"
        case .diskCreationFailed: return "Unable to create the VM disk image"
        }
    }
}
