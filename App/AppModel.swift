import Foundation
import Combine
import AppKit
import Virtualization

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var devices: [StorageDevice] = []
    @Published private(set) var status = "Not scanned"
    @Published private(set) var scanInProgress = false
    @Published private(set) var topology = APFSTopology.empty
    @Published private(set) var apfsStatus = "Not scanned"
    @Published private(set) var installations: [MacOSInstallationCandidate] = []
    @Published var selectedDeviceID: String?
    @Published var vmFolderPath = ""
    @Published var restoreImagePath = ""
    @Published var guestOS: VMGuestOS = .macOS
    @Published var installationISOPath = ""
    @Published var windowsDriverISOPath = ""
    @Published var qemuExecutablePath = ""
    @Published var swtpmExecutablePath = ""
    @Published var windowsFirmwareCodePath = ""
    @Published var windowsFirmwareVariablesPath = ""
    @Published var diskSizeGiB = 80
    @Published private(set) var provisioning = false
    @Published private(set) var installProgress: Double = 0
    @Published private(set) var knownVMs: [(url: URL, record: ManagedVMManifest)] = []
    @Published private(set) var vmRevision = 0
    @Published private(set) var vmStatus = "No VM loaded"
    @Published private(set) var vmOperationInProgress = false
    @Published private(set) var diskImageStatus = "Choose a VM folder to manage its disk images"
    @Published private(set) var diskRevision = 0
    @Published var hardware = VMHardwareSettings.default
    @Published private(set) var hardwareStatus = "Choose a VM to edit its hardware"
    @Published private(set) var hardwareLoaded = false
    @Published private(set) var diskPreflightStatus = "Select a device to inspect physical attachment eligibility."
    @Published private(set) var diskPreflightRunning = false
    private let diskPreflight = PhysicalDiskPreflight()
    private let diskBrokerClient = DiskBrokerClient()
    private let privilegedBroker = PrivilegedBrokerClient()
    @Published var attachDisposableDisk = false
    private var activeDiskGrant: PrivilegedDiskGrant?
    @Published private(set) var privilegedDaemonStatus = "Not checked"
    @Published private(set) var privilegedDaemonDiagnostic = "Not connected"
    @Published private(set) var privilegedDaemonBusy = false
    @Published private(set) var brokerDiagnostic = "Broker not contacted"
    @Published private(set) var brokerDiagnosticRunning = false
    private let inventory = DeviceInventoryService()
    private let apfsInspector = APFSInspector()
    let vm = VMRuntimeService()
    @Published var connectivity = VMConnectivitySettings.default
    @Published private(set) var networkInterfaces: [String] = []
    @Published private(set) var connectivityStatus = "NAT by default. Save settings before starting an installed VM."
    @Published var outgoingMessage = ""
    @Published private(set) var guestMessages: [VBExchangeMessage] = []
    @Published private(set) var guestHeartbeat: VBGuestHeartbeat?
    @Published private(set) var exchangeStatus = "Guest tools disabled"
    @Published private(set) var transferProgress: Double = 0
    @Published private(set) var transferInProgress = false
    @Published private(set) var pairingCode = ""
    @Published private(set) var authenticatedStatus = "Guest not paired"
    @Published private(set) var networkHealth = "Select a VM and check its profile"
    @Published private(set) var clipboardStatus = "Manual text clipboard only; no automatic sync"

    init() {
        vm.onExternalStateChange = { [weak self] status in
            self?.vmStatus = status
            self?.vmRevision += 1
        }
    }

    private func loadGuestDetails(from folder: URL) {
        guard let record = try? VMRegistry.read(at: folder) else { return }
        guestOS = record.guestOS
        installationISOPath = record.installationMediaPath ?? ""
        windowsDriverISOPath = record.driverMediaPath ?? ""
        qemuExecutablePath = record.qemu?.executablePath ?? ""
        swtpmExecutablePath = record.qemu?.swtpmPath ?? ""
    }

    func refreshNetworkInterfaces() {
        networkInterfaces = VZBridgedNetworkInterface.networkInterfaces.map(\.identifier)
    }

    func loadConnectivity() {
        guard !isVMInUse else { connectivityStatus = "Stop the VM before selecting another profile"; return }
        guard vmFolderPath.hasPrefix("/") else { connectivityStatus = "Choose a VM folder"; return }
        do {
            hardware = try VMHardwareStore.load(from: URL(fileURLWithPath: vmFolderPath))
            hardwareLoaded = true
            hardwareStatus = "Hardware profile loaded"
            loadGuestDetails(from: URL(fileURLWithPath: vmFolderPath))
            connectivity = try VMConnectivityStore.load(from: URL(fileURLWithPath: vmFolderPath))
            refreshNetworkInterfaces()
            connectivityStatus = "Loaded VM connectivity profile"
            refreshExchange()
        } catch { connectivityStatus = "Load failed: \(error.localizedDescription)" }
    }

    func saveHardware() {
        guard !isVMInUse else { hardwareStatus = "Stop the VM before changing virtual hardware"; return }
        guard vmFolderPath.hasPrefix("/") else { hardwareStatus = "Choose an installed VM folder"; return }
        let folder = URL(fileURLWithPath: vmFolderPath, isDirectory: true)
        do {
            try VMHardwarePolicy.verify(hardware, vmFolder: folder,
                cpuRange: 2...max(2, ProcessInfo.processInfo.processorCount),
                maximumMemoryGiB: safeMaximumMemoryGiB)
            try VMHardwareStore.save(hardware, to: folder)
            hardwareStatus = "Saved · changes apply the next time this VM starts"
        } catch { hardwareStatus = "Save rejected: \(error.localizedDescription)" }
    }

    var safeMaximumMemoryGiB: Int {
        max(4, min(64, Int(ProcessInfo.processInfo.physicalMemory / 1_073_741_824) - 4))
    }

    func loadHardwareProfile(for folder: URL) {
        guard !isVMInUse else { hardwareStatus = "Stop the VM before selecting another instance"; return }
        vmFolderPath = folder.path
        do {
            hardware = try VMHardwareStore.load(from: folder)
            hardwareLoaded = true
            hardwareStatus = "Hardware profile loaded for \(folder.lastPathComponent)"
            loadGuestDetails(from: folder)
            connectivity = try VMConnectivityStore.load(from: folder)
            connectivityStatus = "Loaded VM connectivity profile"
            refreshNetworkInterfaces()
            refreshExchange()
        } catch { hardwareStatus = "Load failed: \(error.localizedDescription)"; connectivityStatus = hardwareStatus }
    }

    func saveConnectivity() {
        guard !isVMInUse else { connectivityStatus = "Stop the VM before changing virtual devices"; return }
        guard vmFolderPath.hasPrefix("/") else { connectivityStatus = "Choose a VM folder"; return }
        let folder = URL(fileURLWithPath: vmFolderPath, isDirectory: true)
        do {
            refreshNetworkInterfaces()
            try VMConnectivityPolicy.verify(connectivity, vmFolder: folder, validInterfaces: Set(networkInterfaces))
            try VMConnectivityStore.save(connectivity, to: folder)
            if connectivity.guestToolsEnabled {
                try HostGuestExchange.createIfNeeded(in: folder)
                try VBGuestToolsTransport.prepare(root: HostGuestExchange.root(for: folder))
            }
            connectivityStatus = "Saved network and guest-tools settings. Changes take effect on next boot."
        } catch { connectivityStatus = "Save rejected: \(error.localizedDescription)" }
    }

    func refreshExchange() {
        guard vmFolderPath.hasPrefix("/") else { guestMessages = []; guestHeartbeat = nil; return }
        let folder = URL(fileURLWithPath: vmFolderPath)
        guestMessages = HostGuestExchange.receive(for: "host", in: folder)
        guestHeartbeat = HostGuestExchange.guestHeartbeat(in: folder)
        let age = guestHeartbeat.map { Int(max(0, Date().timeIntervalSince($0.timestamp))) }
        networkHealth = "Profile: \(connectivity.networkMode.rawValue.uppercased()) · Guest heartbeat: \(age.map { "\($0)s ago" } ?? "unavailable") · Actual DHCP/internet connectivity not established"
        if let key = try? VBPairing.load(VBPairing.hostKeyPath(folder)) {
            let replies = VBGuestToolsTransport.verifiedReplies(root: HostGuestExchange.root(for: folder), key: key)
            authenticatedStatus = replies.first.map { "Authenticated guest response: \($0.detail)" } ?? "Paired; no authenticated response yet"
        } else { authenticatedStatus = "Not paired; only signed ping/status requests require pairing" }
    }

    func sendHostMessage() {
        guard connectivity.guestToolsEnabled, vmFolderPath.hasPrefix("/") else { exchangeStatus = "Enable guest tools in VM settings"; return }
        do {
            try HostGuestExchange.send(outgoingMessage, from: "host", in: URL(fileURLWithPath: vmFolderPath))
            outgoingMessage = ""
            exchangeStatus = "Message queued in guest exchange"
        } catch { exchangeStatus = "Send failed: \(error.localizedDescription)" }
    }

    func sendHostFile(_ url: URL) {
        guard connectivity.guestToolsEnabled, vmFolderPath.hasPrefix("/") else { exchangeStatus = "Guest tools are disabled"; return }
        guard !transferInProgress else { exchangeStatus = "A transfer is already in progress"; return }
        transferInProgress = true
        transferProgress = 0
        let root = HostGuestExchange.root(for: URL(fileURLWithPath: vmFolderPath))
        Task.detached(priority: .utility) { [weak self] in
            guard let model = self else { return }
            do {
                let receipt = try VBGuestToolsTransport.stageFile(url, origin: "host", root: root) { fraction in
                    Task { @MainActor [weak model] in model?.transferProgress = fraction }
                }
                await MainActor.run {
                    model.transferInProgress = false
                    model.transferProgress = 1
                    model.exchangeStatus = "Staged \(receipt.originalName) (SHA-256 \(receipt.sha256.prefix(12))…)"
                }
            } catch {
                await MainActor.run {
                    model.transferInProgress = false
                    model.exchangeStatus = "File staging failed: \(error.localizedDescription)"
                }
            }
        }
    }

    func showGuestPairingCode() {
        guard connectivity.guestToolsEnabled, vmFolderPath.hasPrefix("/") else { authenticatedStatus = "Enable guest tools first"; return }
        do {
            let key = try VBPairing.createHostKey(URL(fileURLWithPath: vmFolderPath))
            pairingCode = VBSHA256.hex(Array(key))
            authenticatedStatus = "Enter this code inside the guest using: volumeboot-guest-agent pair <code>. Treat it as a secret."
        } catch { authenticatedStatus = "Pairing setup failed: \(error.localizedDescription)" }
    }

    func queueAuthenticatedGuestPing() {
        guard connectivity.guestToolsEnabled, vmFolderPath.hasPrefix("/") else { authenticatedStatus = "Enable guest tools first"; return }
        let folder = URL(fileURLWithPath: vmFolderPath)
        do {
            let key = try VBPairing.load(VBPairing.hostKeyPath(folder))
            let request = try VBGuestToolsTransport.queueRequest(.ping, root: HostGuestExchange.root(for: folder), key: key)
            authenticatedStatus = "Authenticated ping queued (\(request.id)). Refresh after guest agent processes it."
        } catch { authenticatedStatus = "Ping failed: \(error.localizedDescription)" }
    }

    func sendHostClipboard() {
        guard connectivity.guestToolsEnabled, vmFolderPath.hasPrefix("/") else { clipboardStatus = "Enable guest tools"; return }
        guard let text = NSPasteboard.general.string(forType: .string) else { clipboardStatus = "No plain text on host clipboard"; return }
        do {
            try VBGuestToolsTransport.offerClipboard(text, origin: "host", root: HostGuestExchange.root(for: URL(fileURLWithPath: vmFolderPath)))
            clipboardStatus = "Host text offered. Guest must explicitly import it."
        } catch { clipboardStatus = "Clipboard offer failed: \(error.localizedDescription)" }
    }

    func importGuestClipboard() {
        guard connectivity.guestToolsEnabled, vmFolderPath.hasPrefix("/") else { clipboardStatus = "Enable guest tools"; return }
        guard let offer = VBGuestToolsTransport.latestClipboard(for: "host", root: HostGuestExchange.root(for: URL(fileURLWithPath: vmFolderPath))) else {
            clipboardStatus = "No guest clipboard offer"; return
        }
        NSPasteboard.general.clearContents()
        clipboardStatus = NSPasteboard.general.setString(offer.text, forType: .string) ? "Imported guest text into host clipboard" : "Host clipboard refused text"
    }

    func scan() async {
        guard !scanInProgress else { return }
        scanInProgress = true
        defer { scanInProgress = false }
        do {
            devices = try await inventory.listDevices()
            status = "Found \(devices.count) storage records"
            do {
                topology = try await apfsInspector.inspect()
                installations = MacOSInstallationDetector.detect(topology)
                apfsStatus = "\(topology.containers.count) APFS containers, \(topology.containers.reduce(0) { $0 + $1.volumes.count }) volumes"
            } catch {
                topology = .empty
                installations = []
                apfsStatus = "APFS scan unavailable: \(error.localizedDescription)"
            }
        } catch { devices = []; topology = .empty; installations = []; status = "Inventory failed: \(error.localizedDescription)" }
    }

    func checkDiskBroker() async {
        guard !brokerDiagnosticRunning else { return }
        brokerDiagnosticRunning = true
        defer { brokerDiagnosticRunning = false }
        do { brokerDiagnostic = try await diskBrokerClient.diagnostic() }
        catch { brokerDiagnostic = "Broker unavailable: \(error.localizedDescription)" }
    }

    func refreshPrivilegedDaemonStatus() {
        privilegedDaemonStatus = privilegedBroker.currentStatus()
    }

    func registerPrivilegedDaemon() {
        do {
            privilegedDaemonStatus = try privilegedBroker.registerWithUserApproval()
        } catch {
            privilegedDaemonStatus = "Registration failed: \(error.localizedDescription)"
        }
    }

    func openPrivilegedDaemonApproval() { privilegedBroker.openApprovalSettings() }

    func checkPrivilegedDaemon() async {
        guard !privilegedDaemonBusy else { return }
        privilegedDaemonBusy = true
        defer { privilegedDaemonBusy = false }
        do { privilegedDaemonDiagnostic = try await privilegedBroker.checkHealth() }
        catch { privilegedDaemonDiagnostic = "Daemon unavailable: \(error.localizedDescription)" }
        refreshPrivilegedDaemonStatus()
    }

    func checkSelectedPhysicalDevice() async {
        guard let name = selectedDeviceID else { return }
        guard !diskPreflightRunning else { return }
        diskPreflightRunning = true
        defer { diskPreflightRunning = false }
        do {
            let report = try await diskPreflight.inspect(name)
            diskPreflightStatus = "\(report.bsdName) / parent \(report.wholeDisk): " + report.reasons.joined(separator: "; ")
        } catch {
            diskPreflightStatus = "Preflight rejected: \(error.localizedDescription)"
        }
    }

    @Published private(set) var detailedTopologyStatus = "No privileged topology inspection performed"
    @Published private(set) var detailedTopologyBusy = false

    func inspectSelectedDaemonTopology() async {
        guard let name = selectedDeviceID, !detailedTopologyBusy else { return }
        detailedTopologyBusy = true
        defer { detailedTopologyBusy = false }
        do { detailedTopologyStatus = try await privilegedBroker.inspectTopology(name) }
        catch { detailedTopologyStatus = "Topology analysis refused: \(error.localizedDescription)" }
    }

    func apfsVolumes(for device: StorageDevice) -> [APFSVolumeRecord] {
        topology.containers.flatMap(\.volumes).filter { $0.deviceIdentifier == device.identifier }
    }

    func inspect(_ device: StorageDevice) -> CompatibilityVerdict {
        CompatibilityEngine.inspect(device)
    }

    func bootManagedVM() async {
        guard !isVMInUse else { vmStatus = "Stop the current VM before starting another"; return }
        vmOperationInProgress = true
        defer { vmOperationInProgress = false }
        guard vmFolderPath.hasPrefix("/") else { vmStatus = "Select an absolute VM folder path"; return }
        let url = URL(fileURLWithPath: vmFolderPath, isDirectory: true)
        do {
            loadGuestDetails(from: url)
            hardware = try VMHardwareStore.load(from: url)
            connectivity = try VMConnectivityStore.load(from: url)
            var grant: PrivilegedDiskGrant?
            if attachDisposableDisk {
                guard let device = devices.first(where: { $0.id == selectedDeviceID }), device.isWholeDisk else {
                    vmStatus = "Select an entire external disposable test disk first"; return
                }
                grant = try await privilegedBroker.acquireDisposableExternalDisk(device.identifier)
                vmStatus = "Read-only grant acquired for \(device.identifier); starting guest…"
            }
            do {
                try await vm.startExistingVM(at: url, readOnlyDisk: grant?.disk)
                activeDiskGrant = grant
            } catch {
                grant?.releaseAfterVMStops()
                throw error
            }
            vmRevision += 1
            vmStatus = "\(guestOS.title) VM started" + (vm.usesExternalConsole ? " in the QEMU window; Control + Option + G releases input" : "")
        } catch { vmStatus = "Boot failed: \(error.localizedDescription)" }
    }

    func stopVM() async {
        guard !provisioning, !vmOperationInProgress else { return }
        vmOperationInProgress = true
        defer { vmOperationInProgress = false }
        do {
            if !vm.discardAlreadyStoppedSession() { try await vm.stop() }
            activeDiskGrant?.releaseAfterVMStops()
            activeDiskGrant = nil
            vmRevision += 1
            vmStatus = "VM stopped; read-only disk lease released"
        }
        catch { vmStatus = "Stop failed: \(error.localizedDescription)" }
    }
    func refreshManagedVMs() {
        guard vmFolderPath.hasPrefix("/") else { knownVMs = []; return }
        let folder = URL(fileURLWithPath: vmFolderPath, isDirectory: true)
        knownVMs = VMRegistry.discover(in: folder.deletingLastPathComponent())
    }

    func provisionVM() async {
        guard !isVMInUse else { return }
        let mediaPath = guestOS == .macOS ? restoreImagePath : installationISOPath
        guard vmFolderPath.hasPrefix("/"), mediaPath.hasPrefix("/") else {
            vmStatus = "Choose a new VM folder path and local \(guestOS == .macOS ? "IPSW" : "ARM64 ISO")"; return
        }
        provisioning = true
        hardwareLoaded = true
        installProgress = 0
        let progressMonitor = Task { @MainActor in
            while !Task.isCancelled {
                installProgress = vm.installationProgress
                try? await Task.sleep(nanoseconds: 350_000_000)
            }
        }
        vmStatus = "Preparing \(guestOS.title) installation"
        defer { progressMonitor.cancel(); provisioning = false; vmRevision += 1; refreshManagedVMs() }
        do {
            let folder = URL(fileURLWithPath: vmFolderPath, isDirectory: true)
            if guestOS == .macOS {
                try await vm.provision(at: folder, restoreImageURL: URL(fileURLWithPath: restoreImagePath),
                    diskSizeGiB: diskSizeGiB, connectivity: connectivity, hardware: hardware)
                installProgress = 1
                vmStatus = "Installation completed. Start the managed VM to boot macOS."
            } else {
                let tools = guestOS == .windowsARM ? try VMQEMUSettings.discover(qemuPath: qemuExecutablePath, swtpmPath: swtpmExecutablePath) : nil
                let firmwareCode = try tools?.firmware(named: "edk2-aarch64-code.fd", overridePath: windowsFirmwareCodePath)
                let firmwareVars = try tools?.firmware(named: "edk2-arm-vars.fd", overridePath: windowsFirmwareVariablesPath)
                let drivers = windowsDriverISOPath.isEmpty || guestOS != .windowsARM ? nil : URL(fileURLWithPath: windowsDriverISOPath)
                try vm.createARMGuest(at: folder, guestOS: guestOS, installationMediaURL: URL(fileURLWithPath: installationISOPath),
                    diskSizeGiB: diskSizeGiB, connectivity: connectivity, hardware: hardware, qemuSettings: tools,
                    firmwareCodeURL: firmwareCode, firmwareVariablesURL: firmwareVars, driverMediaURL: drivers)
                try await vm.startExistingVM(at: folder)
                vmStatus = "\(guestOS.title) installer running\(vm.usesExternalConsole ? " in the QEMU window" : " in the guest console"). Complete setup, shut down the guest, then Finish installation and eject ISO."
            }
        } catch { vmStatus = "Installation failed: \(error.localizedDescription). Incomplete VM data was retained." }
    }

    var isVMInUse: Bool { provisioning || vmOperationInProgress || vm.operationInProgress || vm.hasSession }

    func finishARMInstallation() {
        guard !isVMInUse else { vmStatus = "Shut down and stop the VM before finishing installation"; return }
        do {
            try vm.finishARMInstallation(at: URL(fileURLWithPath: vmFolderPath))
            refreshManagedVMs()
            vmStatus = "Installation acknowledged; the installer ISO will be ejected on the next boot"
        } catch { vmStatus = "Could not finish installation: \(error.localizedDescription)" }
    }

    func canBeginQuit() -> Bool {
        guard !provisioning, !vmOperationInProgress, !vm.operationInProgress else {
            vmStatus = "Wait for the current VM operation to finish before quitting"
            return false
        }
        return true
    }

    private func updateDiskSelection(_ update: (inout VMHardwareSettings) -> Void) throws {
        guard !isVMInUse else { throw VMDiskImageError.inUse }
        guard vmFolderPath.hasPrefix("/") else { throw VMHardwareError.invalidFolder }
        var next = hardware
        update(&next)
        let folder = URL(fileURLWithPath: vmFolderPath, isDirectory: true)
        try VMHardwarePolicy.verify(next, vmFolder: folder)
        if FileManager.default.fileExists(atPath: folder.appendingPathComponent("manifest.json").path) {
            // Persist disk choices without silently saving other hardware edits.
            var saved = try VMHardwareStore.load(from: folder)
            saved.bootDiskPath = next.bootDiskPath
            saved.additionalDisks = next.additionalDisks
            try VMHardwareStore.save(saved, to: folder)
        }
        hardware = next
        diskRevision += 1
    }

    func selectDiskImage(_ url: URL, asBootDisk: Bool) {
        do {
            let image = try VMDiskImageStore.inspect(at: url)
            try updateDiskSelection { settings in
                if asBootDisk {
                    let defaultDisk = URL(fileURLWithPath: vmFolderPath).appendingPathComponent("disk.img").standardizedFileURL
                    settings.bootDiskPath = image.url == defaultDisk ? nil : image.url.path
                }
                else { settings.additionalDisks.append(VMAdditionalDisk(path: image.url.path)) }
            }
            diskImageStatus = asBootDisk ? "Boot image selected. Use matching VM identity files to run an existing macOS installation." : "Secondary image attached for the next boot"
        } catch { diskImageStatus = "Selection failed: \(error.localizedDescription)" }
    }

    func useBundleBootDisk() {
        do {
            try updateDiskSelection { $0.bootDiskPath = nil }
            diskImageStatus = "Using disk.img in the VM folder"
        } catch { diskImageStatus = "Selection failed: \(error.localizedDescription)" }
    }

    func detachDiskImage(_ disk: VMAdditionalDisk) {
        do {
            try updateDiskSelection { $0.additionalDisks.removeAll { $0.id == disk.id } }
            diskImageStatus = "Image detached; the file remains on disk"
        } catch { diskImageStatus = "Detach failed: \(error.localizedDescription)" }
    }

    func createDiskImage(at url: URL, sizeGiB: Int, asBootDisk: Bool) {
        guard !isVMInUse else { diskImageStatus = VMDiskImageError.inUse.localizedDescription; return }
        do {
            _ = try VMDiskImageStore.capacityBytes(sizeGiB, bootDisk: asBootDisk)
            try VMDiskImageStore.create(at: url, sizeGiB: sizeGiB)
            selectDiskImage(url, asBootDisk: asBootDisk)
            diskImageStatus = "Created \(sizeGiB) GiB image. \(diskImageStatus)"
        } catch { diskImageStatus = "Creation failed: \(error.localizedDescription)" }
        diskRevision += 1
    }

    func growDiskImage(at url: URL, toGiB sizeGiB: Int) {
        guard !isVMInUse else { diskImageStatus = VMDiskImageError.inUse.localizedDescription; return }
        do {
            let image = try VMDiskImageStore.grow(at: url, toGiB: sizeGiB)
            let folder = URL(fileURLWithPath: vmFolderPath)
            if hardware.bootDiskURL(in: folder).standardizedFileURL == image.url,
               var manifest = try? VMRegistry.read(at: folder) {
                manifest.diskSizeGiB = sizeGiB
                try VMRegistry.write(manifest, at: folder)
                refreshManagedVMs()
            }
            diskImageStatus = "Image grown to \(sizeGiB) GiB. Expand the partition and APFS container inside macOS to use the new space."
        } catch { diskImageStatus = "Resize failed: \(error.localizedDescription)" }
        diskRevision += 1
    }

    func deleteDiskImage(at url: URL) {
        guard !isVMInUse else { diskImageStatus = VMDiskImageError.inUse.localizedDescription; return }
        do {
            let lease = try VMDiskImageLease(url: url)
            let isBootDisk = hardware.bootDiskURL(in: URL(fileURLWithPath: vmFolderPath)).standardizedFileURL == lease.info.url
            let previous = hardware
            if !isBootDisk {
                // Persist detachment before deletion, while keeping the file locked.
                try updateDiskSelection { $0.additionalDisks.removeAll { URL(fileURLWithPath: $0.path).standardizedFileURL == lease.info.url } }
            }
            do { try VMDiskImageStore.delete(lease) }
            catch {
                if !isBootDisk { try? updateDiskSelection { $0 = previous } }
                throw error
            }
            diskRevision += 1
            diskImageStatus = "Deleted \(url.lastPathComponent)"
            // Keep a missing boot-image reference visible; never switch boot disks implicitly.
            if isBootDisk {
                diskImageStatus += ". Select a replacement boot image before starting this VM."
            }
        } catch { diskImageStatus = "Disk operation failed: \(error.localizedDescription)" }
    }

}
