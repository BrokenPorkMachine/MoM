import Foundation
import Virtualization

@MainActor
final class VMRuntimeService {
    enum RuntimeError: LocalizedError {
        case unsupportedHost, missingMetadata(String), invalidMetadata(String), noVM, busy, incompleteInstallation, unsafeDestination
        var errorDescription: String? {
            switch self {
            case .unsupportedHost: return "macOS guest virtualization requires an Apple Silicon host"
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
    private(set) var installer: VZMacOSInstaller?
    var installationProgress: Double { installer?.progress.fractionCompleted ?? 0 }
    private(set) var currentFolder: URL?
    private var physicalDiskLease: ReadOnlyPhysicalDiskLease?

    func startExistingVM(at folder: URL, readOnlyDisk: ReadOnlyPhysicalDiskLease? = nil) async throws {
        #if arch(arm64)
        guard virtualMachine == nil else { throw RuntimeError.busy }
        let manifest = try VMRegistry.read(at: folder)
        guard manifest.state == .installed else { throw RuntimeError.incompleteInstallation }
        let connectivity = try VMConnectivityStore.load(from: folder)
        if connectivity.guestToolsEnabled { try HostGuestExchange.createIfNeeded(in: folder) }
        let hardware = try VMHardwareStore.load(from: folder)
        try VMHardwarePolicy.verify(hardware, vmFolder: folder,
            cpuRange: VZVirtualMachineConfiguration.minimumAllowedCPUCount...VZVirtualMachineConfiguration.maximumAllowedCPUCount,
            maximumMemoryGiB: Int(VZVirtualMachineConfiguration.maximumAllowedMemorySize / 1_073_741_824))
        let config = try makeConfiguration(folder: folder, hardware: hardware, readOnlyDisk: readOnlyDisk)
        let vm = VZVirtualMachine(configuration: config)
        virtualMachine = vm
        physicalDiskLease = readOnlyDisk
        currentFolder = folder
        do { try await vm.start() } catch { virtualMachine = nil; physicalDiskLease = nil; currentFolder = nil; throw error }
        #else
        throw RuntimeError.unsupportedHost
        #endif
    }

    /// A guest can stop on its own; permit safe lease cleanup without invoking
    /// `stop()` a second time on an already stopped VM.
    func discardAlreadyStoppedSession() -> Bool {
        guard let vm = virtualMachine else { return true }
        guard vm.state == .stopped || vm.state == .error else { return false }
        virtualMachine = nil
        physicalDiskLease = nil
        currentFolder = nil
        return true
    }

    func stop() async throws {
        guard let virtualMachine else { throw RuntimeError.noVM }
        try await virtualMachine.stop()
        self.virtualMachine = nil
        physicalDiskLease = nil
        currentFolder = nil
    }
    #if arch(arm64)
    private func makeConfiguration(folder: URL, hardware: VMHardwareSettings, readOnlyDisk: ReadOnlyPhysicalDiskLease? = nil) throws -> VZVirtualMachineConfiguration {
        func file(_ name: String) throws -> URL {
            let url = folder.appendingPathComponent(name)
            guard FileManager.default.fileExists(atPath: url.path) else { throw RuntimeError.missingMetadata(name) }
            return url
        }
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
        let config = VZVirtualMachineConfiguration()
        config.platform = platform
        config.bootLoader = VZMacOSBootLoader()
        config.cpuCount = hardware.cpuCount
        config.memorySize = UInt64(hardware.memoryGiB) * 1_073_741_824
        let attachment = try VZDiskImageStorageDeviceAttachment(url: try file("disk.img"), readOnly: false)
        config.storageDevices = [VZVirtioBlockDeviceConfiguration(attachment: attachment)]
        for disk in hardware.additionalDisks {
            let image = try VZDiskImageStorageDeviceAttachment(url: URL(fileURLWithPath: disk.path), readOnly: disk.readOnly)
            config.storageDevices.append(VZVirtioBlockDeviceConfiguration(attachment: image))
        }
        if let readOnlyDisk { config.storageDevices.append(try readOnlyDisk.makeDevice()) }
        let graphics = VZMacGraphicsDeviceConfiguration()
        graphics.displays = [VZMacGraphicsDisplayConfiguration(widthInPixels: hardware.display.width,
            heightInPixels: hardware.display.height, pixelsPerInch: hardware.display.pixelsPerInch)]
        config.graphicsDevices = [graphics]
        config.keyboards = [hardware.keyboard == .mac ? VZMacKeyboardConfiguration() : VZUSBKeyboardConfiguration()]
        config.pointingDevices = [hardware.pointer == .trackpad ? VZMacTrackpadConfiguration() : VZUSBScreenCoordinatePointingDeviceConfiguration()]
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
            let sharing = VZVirtioFileSystemDeviceConfiguration(tag: VZVirtioFileSystemDeviceConfiguration.macOSGuestAutomountTag)
            sharing.share = VZMultipleDirectoryShare(directories: directories)
            config.directorySharingDevices = [sharing]
        }
        try config.validate()
        return config
    }
    #endif

    /// Creates a managed VM folder and installs macOS from an Apple IPSW restore image.
    /// Does not mount or modify physical storage devices. Incomplete folders are retained for investigation.
    func provision(at folder: URL, restoreImageURL: URL, diskSizeGiB: Int, connectivity: VMConnectivitySettings = .default,
                   hardware: VMHardwareSettings = .default) async throws {
        #if arch(arm64)
        guard virtualMachine == nil else { throw RuntimeError.busy }
        guard folder.isFileURL && !folder.path.hasPrefix("/dev/") && folder.lastPathComponent != "" else { throw RuntimeError.unsafeDestination }
        guard restoreImageURL.isFileURL, restoreImageURL.pathExtension.lowercased() == "ipsw" else {
            throw ProvisioningError.invalidRestoreImage
        }
        guard diskSizeGiB >= 64 && diskSizeGiB <= 2048 else { throw ProvisioningError.invalidDiskSize }
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
        var manifest = ManagedVMManifest(version: 2, id: UUID(), createdAt: Date(), diskSizeGiB: diskSizeGiB, state: .provisioning, lastFailure: nil)
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
            let diskURL = folder.appendingPathComponent("disk.img")
            guard FileManager.default.createFile(atPath: diskURL.path, contents: nil) else {
                throw ProvisioningError.diskCreationFailed
            }
            let handle = try FileHandle(forWritingTo: diskURL)
            defer { try? handle.close() }
            try handle.truncate(atOffset: UInt64(diskSizeGiB) * 1_073_741_824)
            let config = try makeConfiguration(folder: folder, hardware: hardware)
            let vm = VZVirtualMachine(configuration: config)
            virtualMachine = vm
            let macInstaller = VZMacOSInstaller(virtualMachine: vm, restoringFrom: restoreImageURL)
            installer = macInstaller
            defer { installer = nil; virtualMachine = nil }
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
        #else
        throw RuntimeError.unsupportedHost
        #endif
    }
}

enum VMInstallState: String, Codable { case provisioning, installed, failed }

struct ManagedVMManifest: Codable, Identifiable {
    let version: Int
    let id: UUID
    let createdAt: Date
    let diskSizeGiB: Int
    var state: VMInstallState
    var lastFailure: String?
}

enum VMRegistry {
    static func read(at folder: URL) throws -> ManagedVMManifest {
        try JSONDecoder().decode(ManagedVMManifest.self, from: Data(contentsOf: folder.appendingPathComponent("manifest.json")))
    }
    static func write(_ manifest: ManagedVMManifest, at folder: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(manifest).write(to: folder.appendingPathComponent("manifest.json"), options: .atomic)
    }
    /// Enumerates only immediate child bundles of a user-selected parent directory.
    static func discover(in directory: URL) -> [(url: URL, record: ManagedVMManifest)] {
        guard let children = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else { return [] }
        return children.compactMap { url in
            guard (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true,
                  let record = try? read(at: url) else { return nil }
            return (url: url, record: record)
        }.sorted { $0.record.createdAt > $1.record.createdAt }
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
