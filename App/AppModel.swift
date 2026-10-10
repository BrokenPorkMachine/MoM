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
    @Published var diskSizeGiB = 80
    @Published private(set) var provisioning = false
    @Published private(set) var installProgress: Double = 0
    @Published private(set) var knownVMs: [(url: URL, record: ManagedVMManifest)] = []
    @Published private(set) var vmRevision = 0
    @Published private(set) var vmStatus = "No VM loaded"
    @Published var cpuCount = 2
    @Published var memoryGiB = 4
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

    func refreshNetworkInterfaces() {
        networkInterfaces = VZBridgedNetworkInterface.networkInterfaces.map(\.identifier)
    }

    func loadConnectivity() {
        guard vmFolderPath.hasPrefix("/") else { connectivityStatus = "Choose a VM folder"; return }
        do {
            connectivity = try VMConnectivityStore.load(from: URL(fileURLWithPath: vmFolderPath))
            refreshNetworkInterfaces()
            connectivityStatus = "Loaded VM connectivity profile"
            refreshExchange()
        } catch { connectivityStatus = "Load failed: \(error.localizedDescription)" }
    }

    func saveConnectivity() {
        guard vm.virtualMachine == nil, !provisioning else { connectivityStatus = "Stop the VM before changing virtual devices"; return }
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
            do {
                let receipt = try VBGuestToolsTransport.stageFile(url, origin: "host", root: root) { fraction in
                    Task { @MainActor [weak self] in self?.transferProgress = fraction }
                }
                await MainActor.run {
                    self?.transferInProgress = false
                    self?.transferProgress = 1
                    self?.exchangeStatus = "Staged \(receipt.originalName) (SHA-256 \(receipt.sha256.prefix(12))…)"
                }
            } catch {
                await MainActor.run {
                    self?.transferInProgress = false
                    self?.exchangeStatus = "File staging failed: \(error.localizedDescription)"
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
        guard vmFolderPath.hasPrefix("/") else { vmStatus = "Select an absolute VM folder path"; return }
        let url = URL(fileURLWithPath: vmFolderPath, isDirectory: true)
        do {
            var grant: PrivilegedDiskGrant?
            if attachDisposableDisk {
                guard let device = devices.first(where: { $0.id == selectedDeviceID }), device.isWholeDisk else {
                    vmStatus = "Select an entire external disposable test disk first"; return
                }
                grant = try await privilegedBroker.acquireDisposableExternalDisk(device.identifier)
                vmStatus = "Read-only grant acquired for \(device.identifier); starting guest…"
            }
            do {
                try await vm.startExistingVM(at: url, cpuCount: cpuCount,
                    memoryBytes: UInt64(memoryGiB) * 1_073_741_824, readOnlyDisk: grant?.disk)
                activeDiskGrant = grant
            } catch {
                grant?.releaseAfterVMStops()
                throw error
            }
            vmRevision += 1
            vmStatus = "Managed VM started"
        } catch { vmStatus = "Boot failed: \(error.localizedDescription)" }
    }

    func stopVM() async {
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
        guard !provisioning else { return }
        guard vmFolderPath.hasPrefix("/"), restoreImagePath.hasPrefix("/") else {
            vmStatus = "Choose a destination folder path and local IPSW"; return
        }
        provisioning = true
        installProgress = 0
        let progressMonitor = Task { @MainActor in
            while !Task.isCancelled {
                installProgress = vm.installationProgress
                try? await Task.sleep(nanoseconds: 350_000_000)
            }
        }
        vmStatus = "Provisioning macOS from restore image (do not quit the application)"
        defer { progressMonitor.cancel(); provisioning = false; vmRevision += 1; refreshManagedVMs() }
        do {
            try await vm.provision(
                at: URL(fileURLWithPath: vmFolderPath, isDirectory: true),
                restoreImageURL: URL(fileURLWithPath: restoreImagePath),
                cpuCount: cpuCount,
                memoryBytes: UInt64(memoryGiB) * 1_073_741_824,
                diskSizeGiB: diskSizeGiB,
                connectivity: connectivity
            )
            installProgress = 1
            vmStatus = "Installation completed. Start the managed VM to boot macOS."
        } catch { vmStatus = "Installation failed: \(error.localizedDescription). Incomplete VM data was retained." }
    }

}
