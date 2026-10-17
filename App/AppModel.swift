import Foundation
import Combine
import AppKit
import Virtualization

protocol VMPreferences {
    func stringArray(forKey key: String) -> [String]?
    func set(_ value: Any?, forKey key: String)
}
extension UserDefaults: VMPreferences {}

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
    @Published var macOSInstallerVersion = ""
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
    @Published private(set) var selectedManifest: ManagedVMManifest?
    @Published private(set) var vmFailure: String?
    @Published private(set) var shutdownRequested = false
    @Published private(set) var validationIssues: [String] = []
    @Published private(set) var validationSummary: String?
    @Published private(set) var workspaceRevision = 0
    @Published private(set) var backendApprovalRequest: VMBackendExecutableIdentity?
    private var loadedFolderPath: String?
    private var savedHardware: VMHardwareSettings?
    private var savedConnectivity: VMConnectivitySettings?
    private let preferences: (any VMPreferences)?
    private let backendTrustStore = VMBackendExecutableTrustStore.shared
    private var pendingBackendAction: BackendApprovalAction?
    private var recentPaths: [String] = []

    private enum BackendApprovalAction { case start, provision }
    @Published private(set) var diskImageStatus = "Choose a VM folder to manage its disk images"
    @Published private(set) var diskRevision = 0
    @Published var hardware = VMHardwareSettings.default
    @Published private(set) var hardwareStatus = "Choose a VM to edit its hardware"
    @Published private(set) var hardwareLoaded = false
    @Published private(set) var diskPreflightStatus = "Select a host disk for read-only metadata diagnostics."
    @Published private(set) var diskPreflightRunning = false
    private let diskPreflight = PhysicalDiskPreflight()
    private let diskBrokerClient = DiskBrokerClient()
    private let privilegedBroker = PrivilegedBrokerClient()
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
    @Published private(set) var guestTransfers: [VBVerifiedTransfer] = []
    @Published private(set) var guestHeartbeat: VBGuestHeartbeat?
    @Published private(set) var exchangeStatus = "Guest tools disabled"
    @Published private(set) var transferProgress: Double = 0
    @Published private(set) var transferInProgress = false
    @Published private(set) var pairingCode = ""
    @Published private(set) var authenticatedStatus = "Guest not paired"
    @Published private(set) var networkHealth = "Select a VM and check its profile"
    @Published private(set) var clipboardStatus = "Manual text clipboard only; no automatic sync"
    @Published private(set) var mediaDownloadInProgress = false
    @Published private(set) var mediaDownloadStatus = ""
    @Published private(set) var osDownloads: [OSMediaDownloadRecord] = []
    private let mediaDownloader = OSMediaDownloader()
    private var activeMediaDownloadID: UUID?

    init(preferences: (any VMPreferences)? = nil) {
        self.preferences = preferences
        recentPaths = (preferences?.stringArray(forKey: "recentVMPaths") ?? []).filter { $0.hasPrefix("/") }
            .map { URL(fileURLWithPath: $0).standardizedFileURL.resolvingSymlinksInPath().path }
        vm.onExternalStateChange = { [weak self] status in
            guard let self else { return }
            self.shutdownRequested = false
            self.vmStatus = status
            self.vmRevision += 1
        }
        refreshManagedVMs()
        if preferences != nil, let path = recentPaths.first,
           (try? VMRegistry.read(at: URL(fileURLWithPath: path))) != nil {
            loadHardwareProfile(for: URL(fileURLWithPath: path))
        }
    }

    func downloadLatestMacOSRestoreImage(to destination: URL) {
        guard !mediaDownloadInProgress else { return }
        mediaDownloadInProgress = true
        mediaDownloadStatus = "Finding the latest Apple restore image…"
        let recordID = UUID()
        activeMediaDownloadID = recordID
        osDownloads.insert(OSMediaDownloadRecord(id: recordID, title: "Latest macOS restore image", destination: destination,
                                                   progress: 0, state: .downloading, detail: destination.path), at: 0)
        mediaDownloader.downloadLatestMacOSRestoreImage(to: destination, progress: { [weak self] value in
            guard let self, self.activeMediaDownloadID == recordID else { return }
            if let index = self.osDownloads.firstIndex(where: { $0.id == recordID }) { self.osDownloads[index].progress = value }
            self.mediaDownloadStatus = "Downloading Apple restore image… \(Int(value * 100))%"
        }) { [weak self] result in
            guard let self, self.activeMediaDownloadID == recordID else { return }
            self.activeMediaDownloadID = nil
            self.mediaDownloadInProgress = false
            switch result {
            case .success(let url):
                self.restoreImagePath = url.path
                self.mediaDownloadStatus = "Downloaded Apple restore image."
                self.updateDownload(recordID, state: .completed, detail: url.path, progress: 1)
            case .failure(let error):
                self.mediaDownloadStatus = "Download failed: \(error.localizedDescription)"
                self.updateDownload(recordID, state: error is CancellationError ? .cancelled : .failed,
                                    detail: error.localizedDescription, progress: 0)
            }
        }
    }

    private func updateDownload(_ id: UUID, state: OSMediaDownloadRecord.State, detail: String, progress: Double) {
        guard let index = osDownloads.firstIndex(where: { $0.id == id }) else { return }
        osDownloads[index].state = state
        osDownloads[index].detail = detail
        osDownloads[index].progress = progress
    }

    func cancelMediaDownload() {
        mediaDownloader.cancel()
        mediaDownloadInProgress = false
        mediaDownloadStatus = "Download cancelled."
        if let id = activeMediaDownloadID {
            updateDownload(id, state: .cancelled, detail: "Download cancelled.", progress: 0)
            activeMediaDownloadID = nil
        }
    }

    func openTerminalForMacOSInstallerList() {
        runTerminalCommand("softwareupdate --list-full-installers")
    }

    func openTerminalForMacOSInstallerDownload() {
        let version = macOSInstallerVersion.trimmingCharacters(in: .whitespacesAndNewlines)
        guard version.range(of: #"^\d+(\.\d+){1,2}$"#, options: .regularExpression) != nil else {
            mediaDownloadStatus = "Enter a macOS version such as 26.6.2 before opening Terminal."
            return
        }
        runTerminalCommand("softwareupdate --fetch-full-installer --full-installer-version \(version)")
        mediaDownloadStatus = "Terminal opened. macOS will download the installer to Applications."
    }

    private func runTerminalCommand(_ command: String) {
        let escaped = command.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let script = "tell application \"Terminal\" to do script \"\(escaped)\""
        NSAppleScript(source: script)?.executeAndReturnError(nil)
    }

    var currentManifest: ManagedVMManifest? { loadedFolderPath == vmFolderPath ? selectedManifest : nil }
    var hasUnsavedHardware: Bool { currentManifest != nil && savedHardware != nil && hardware != savedHardware }
    var hasUnsavedConnectivity: Bool { currentManifest != nil && savedConnectivity != nil && connectivity != savedConnectivity }
    var hasUnsavedMedia: Bool {
        guard let record = currentManifest, record.guestOS != .macOS else { return false }
        return installationISOPath != (record.installationMediaPath ?? "") ||
            windowsDriverISOPath != (record.driverMediaPath ?? "") ||
            qemuExecutablePath != (record.qemu?.executablePath ?? "") ||
            swtpmExecutablePath != (record.qemu?.swtpmPath ?? "")
    }
    var hasDraftConfiguration: Bool {
        currentManifest == nil && (!vmFolderPath.isEmpty || guestOS != .macOS || hardware != .default ||
            connectivity != .default || diskSizeGiB != 80 || !restoreImagePath.isEmpty || !installationISOPath.isEmpty ||
            !windowsDriverISOPath.isEmpty || !qemuExecutablePath.isEmpty || !swtpmExecutablePath.isEmpty ||
            !windowsFirmwareCodePath.isEmpty || !windowsFirmwareVariablesPath.isEmpty)
    }
    var hasUnsavedChanges: Bool { hasUnsavedHardware || hasUnsavedConnectivity || hasUnsavedMedia || hasDraftConfiguration }
    var canSelectVM: Bool { !isVMInUse && !transferInProgress }
    var canStartVM: Bool {
        guard !isVMInUse, !hasUnsavedChanges, let record = currentManifest else { return false }
        return record.state == .installed || (record.guestOS != .macOS && record.state == .installing)
    }
    var canFinishInstallation: Bool { !isVMInUse && currentManifest?.state == .installing && guestOS != .macOS }
    var maximumCPUCount: Int { max(2, min(ProcessInfo.processInfo.processorCount, VZVirtualMachineConfiguration.maximumAllowedCPUCount)) }
    var canCreateVM: Bool {
        let media = guestOS == .macOS ? restoreImagePath : installationISOPath
        return !isVMInUse && currentManifest == nil && vmFolderPath.hasPrefix("/") && media.hasPrefix("/") &&
            !FileManager.default.fileExists(atPath: vmFolderPath)
    }

    func validateVMConfiguration() {
        guard let record = currentManifest else { return }
        if hasUnsavedChanges {
            validationIssues = ["Save or reload your edits before validating the saved configuration."]
        } else {
            refreshNetworkInterfaces()
            validationIssues = VMReadiness.issues(folder: URL(fileURLWithPath: vmFolderPath), record: record,
                hardware: hardware, connectivity: connectivity, interfaces: Set(networkInterfaces),
                cpuRange: 2...maximumCPUCount, maximumMemoryGiB: safeMaximumMemoryGiB)
        }
        validationSummary = validationIssues.isEmpty ? "File and policy checks passed. The backend validates the full configuration at startup." : validationIssues.joined(separator: "\n")
    }

    func beginNewVM() {
        guard canSelectVM else { return }
        vmFolderPath = ""; selectedManifest = nil; loadedFolderPath = nil
        savedHardware = nil; savedConnectivity = nil; hardwareLoaded = false
        hardware = .default; connectivity = .default; guestOS = .macOS
        restoreImagePath = ""; installationISOPath = ""; windowsDriverISOPath = ""
        qemuExecutablePath = ""; swtpmExecutablePath = ""
        windowsFirmwareCodePath = ""; windowsFirmwareVariablesPath = ""
        vmFailure = nil; vmStatus = "Configure a new virtual machine"
        validationIssues = []; validationSummary = nil
        outgoingMessage = ""; guestMessages = []; guestTransfers = []; guestHeartbeat = nil; pairingCode = ""
        hardwareStatus = "New VM hardware applies during installation"
        connectivityStatus = "NAT by default. Settings apply during installation."
        diskImageStatus = "Choose a workspace destination before attaching disk images"
        exchangeStatus = "Guest tools disabled"; authenticatedStatus = "Guest not paired"
        networkHealth = "Select a VM and check its profile"; transferProgress = 0
        clipboardStatus = "Manual text clipboard only; no automatic sync"
        diskSizeGiB = 80; diskRevision += 1
        workspaceRevision += 1
    }

    func selectNewGuest(_ guest: VMGuestOS) {
        guard !isVMInUse, currentManifest == nil else { return }
        guestOS = guest
        if guest != .macOS {
            hardware.keyboard = .usb; hardware.pointer = .mouse; connectivity.guestToolsEnabled = false
        }
        if guest == .windowsARM {
            hardware.microphoneEnabled = false
            connectivity.sharedFolderPath = nil
            if connectivity.networkMode == .bridged { connectivity.networkMode = .nat }
        }
    }

    private func loadGuestDetails(from folder: URL, record suppliedRecord: ManagedVMManifest? = nil) {
        guard let record = suppliedRecord ?? (try? VMRegistry.read(at: folder)) else { return }
        selectedManifest = record
        loadedFolderPath = folder.path
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
        guard vmFolderPath.hasPrefix("/") else { connectivityStatus = "Choose a VM folder"; return }
        loadHardwareProfile(for: URL(fileURLWithPath: vmFolderPath))
    }

    func saveHardware() {
        guard !isVMInUse else { hardwareStatus = "Stop the VM before changing virtual hardware"; return }
        guard vmFolderPath.hasPrefix("/") else { hardwareStatus = "Choose an installed VM folder"; return }
        let folder = URL(fileURLWithPath: vmFolderPath, isDirectory: true)
        do {
            try VMHardwarePolicy.verify(hardware, vmFolder: folder,
                cpuRange: 2...maximumCPUCount,
                maximumMemoryGiB: safeMaximumMemoryGiB)
            let record = try VMRegistry.read(at: folder)
            try VMWorkspaceTransaction.commit(at: folder, manifest: record, hardware: hardware, connectivity: connectivity)
            savedHardware = hardware
            hardwareStatus = "Saved · changes apply the next time this VM starts"
        } catch { hardwareStatus = "Save rejected: \(error.localizedDescription)" }
    }

    var safeMaximumMemoryGiB: Int {
        max(4, min(Int(VZVirtualMachineConfiguration.maximumAllowedMemorySize / 1_073_741_824),
                   Int(ProcessInfo.processInfo.physicalMemory / 1_073_741_824) - 4))
    }

    func loadHardwareProfile(for folder: URL) {
        let folder = folder.standardizedFileURL.resolvingSymlinksInPath()
        guard canSelectVM else { hardwareStatus = "Stop the VM and finish transfers before selecting another instance"; return }
        do {
            // Load everything before publishing any selection: failures preserve the previous VM.
            let record = try VMRegistry.read(at: folder)
            let nextHardware = try VMHardwareStore.load(from: folder)
            var nextConnectivity = try VMConnectivityStore.load(from: folder)
            let disabledBridgeProfile = nextConnectivity.networkMode == .bridged && !ReleaseFeaturePolicy.bridgedNetworkingEnabled
            if disabledBridgeProfile {
                nextConnectivity.networkMode = .nat
                nextConnectivity.bridgedInterfaceID = nil
            }
            vmFolderPath = folder.path
            hardware = nextHardware; savedHardware = nextHardware
            connectivity = nextConnectivity; savedConnectivity = nextConnectivity
            selectedManifest = record; loadedFolderPath = folder.path
            hardwareLoaded = true
            hardwareStatus = "Hardware profile loaded for \(folder.lastPathComponent)"
            loadGuestDetails(from: folder, record: record)
            connectivityStatus = disabledBridgeProfile
                ? "Loaded profile with bridged networking disabled in this release; NAT selected. Save the profile to keep this setting."
                : "Loaded VM connectivity profile"
            vmFailure = nil; vmStatus = "\(record.guestOS.title) selected · \(record.state.rawValue)"
            validationIssues = []; validationSummary = nil
            windowsFirmwareCodePath = ""; windowsFirmwareVariablesPath = ""
            outgoingMessage = ""; pairingCode = ""; diskRevision += 1
            workspaceRevision += 1
            recentPaths.removeAll { $0 == folder.path }
            recentPaths.insert(folder.path, at: 0)
            recentPaths = Array(recentPaths.prefix(30))
            preferences?.set(recentPaths, forKey: "recentVMPaths")
            refreshManagedVMs()
            refreshNetworkInterfaces()
            refreshExchange()
        } catch {
            hardwareStatus = "Load failed: \(error.localizedDescription)"; connectivityStatus = hardwareStatus
            vmFailure = error.localizedDescription; vmStatus = "Could not open the VM folder"
        }
    }

    func saveConnectivity() {
        guard !isVMInUse else { connectivityStatus = "Stop the VM before changing virtual devices"; return }
        guard vmFolderPath.hasPrefix("/") else { connectivityStatus = "Choose a VM folder"; return }
        let folder = URL(fileURLWithPath: vmFolderPath, isDirectory: true)
        do {
            refreshNetworkInterfaces()
            try VMConnectivityPolicy.verify(connectivity, vmFolder: folder, validInterfaces: Set(networkInterfaces))
            if currentManifest?.guestOS == .windowsARM {
                guard connectivity.networkMode != .bridged, connectivity.sharedFolderPath == nil,
                      !connectivity.guestToolsEnabled else { throw VMGuestError.unsupportedWindowsSettings }
            }
            try VMConnectivityStore.save(connectivity, to: folder)
            if connectivity.guestToolsEnabled {
                try HostGuestExchange.createIfNeeded(in: folder)
                try VBGuestToolsTransport.prepare(root: HostGuestExchange.root(for: folder))
            }
            savedConnectivity = connectivity
            connectivityStatus = "Saved network and guest-tools settings. Changes take effect on next boot."
        } catch { connectivityStatus = "Save rejected: \(error.localizedDescription)" }
    }

    func refreshExchange() {
        guard vmFolderPath.hasPrefix("/") else { guestMessages = []; guestTransfers = []; guestHeartbeat = nil; return }
        let folder = URL(fileURLWithPath: vmFolderPath)
        guestMessages = HostGuestExchange.receive(for: "host", in: folder)
        guestHeartbeat = HostGuestExchange.guestHeartbeat(in: folder)
        let root = HostGuestExchange.root(for: folder)
        if let key = try? VBPairing.load(VBPairing.hostKeyPath(folder)) {
            guestTransfers = VBGuestToolsTransport.verifiedTransfers(origin: "guest", root: root, key: key)
        } else { guestTransfers = [] }
        let age = guestHeartbeat.map { Int(max(0, Date().timeIntervalSince($0.timestamp))) }
        networkHealth = "Profile: \(connectivity.networkMode.rawValue.uppercased()) · Guest heartbeat: \(age.map { "\($0)s ago" } ?? "unavailable") · Actual DHCP/internet connectivity not established"
        if let key = try? VBPairing.load(VBPairing.hostKeyPath(folder)) {
            let replies = VBGuestToolsTransport.verifiedReplies(root: HostGuestExchange.root(for: folder), key: key)
            authenticatedStatus = replies.first.map { "Authenticated guest response: \($0.detail)" } ?? "Paired; no authenticated response yet"
        } else { authenticatedStatus = "Not paired; pair to authenticate file transfers and guest requests" }
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
        let folder = URL(fileURLWithPath: vmFolderPath)
        Task.detached(priority: .utility) { [weak self] in
            guard let model = self else { return }
            do {
                var lastProgressUpdate = Date.distantPast
                let key = try VBPairing.load(VBPairing.hostKeyPath(folder))
                let receipt = try VBGuestToolsTransport.stageFile(url, origin: "host", root: root, key: key) { fraction in
                    let now = Date()
                    guard fraction >= 1 || now.timeIntervalSince(lastProgressUpdate) >= 0.1 else { return }
                    lastProgressUpdate = now
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

    func receiveGuestTransfer(_ transfer: VBVerifiedTransfer, destination: URL) {
        guard vmFolderPath.hasPrefix("/") else { exchangeStatus = "Choose a VM first"; return }
        do {
            let folder = URL(fileURLWithPath: vmFolderPath)
            let key = try VBPairing.load(VBPairing.hostKeyPath(folder))
            let saved = try VBGuestToolsTransport.receiveTransfer(id: transfer.id, origin: "guest",
                root: HostGuestExchange.root(for: folder), key: key, destination: destination)
            exchangeStatus = "Verified and saved \(saved.lastPathComponent)"
        } catch { exchangeStatus = "Receive failed: \(error.localizedDescription)" }
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
        async let deviceScan = inventory.listDevices()
        async let topologyScan = apfsInspector.inspect()
        do {
            devices = try await deviceScan
            status = "Found \(devices.count) storage records"
        } catch {
            devices = []
            status = "Inventory failed: \(error.localizedDescription)"
        }
        do {
            topology = try await topologyScan
            installations = MacOSInstallationDetector.detect(topology)
            apfsStatus = "\(topology.containers.count) APFS containers, \(topology.containers.reduce(0) { $0 + $1.volumes.count }) volumes"
        } catch {
            topology = .empty
            installations = []
            apfsStatus = "APFS scan unavailable: \(error.localizedDescription)"
        }
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

    func unregisterPrivilegedDaemon() {
        do {
            privilegedDaemonStatus = try privilegedBroker.unregister()
        } catch {
            privilegedDaemonStatus = "Removal failed: \(error.localizedDescription)"
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
        guard !hasUnsavedChanges else { vmStatus = "Save or reload your changes before starting this VM"; return }
        guard vmFolderPath.hasPrefix("/") else { vmStatus = "Select an absolute VM folder path"; return }
        let url = URL(fileURLWithPath: vmFolderPath, isDirectory: true)
        do {
            let record = try VMRegistry.read(at: url)
            if record.guestOS == .windowsARM {
                guard let settings = record.qemu else { throw VMGuestError.missingTool("saved QEMU settings") }
                guard try requestBackendApprovalIfNeeded(settings, action: .start) else { return }
            }
        } catch { vmFailure = error.localizedDescription; vmStatus = "Backend check failed: \(error.localizedDescription)"; return }
        vmFailure = nil; shutdownRequested = false
        vmOperationInProgress = true
        defer { vmOperationInProgress = false }
        do {
            loadGuestDetails(from: url)
            hardware = try VMHardwareStore.load(from: url)
            connectivity = try VMConnectivityStore.load(from: url)
            try await vm.startExistingVM(at: url)
            vmRevision += 1
            vmStatus = "\(guestOS.title) VM started" + (vm.usesExternalConsole ? " in the QEMU window; Control + Option + G releases input" : "")
        } catch { vmFailure = error.localizedDescription; vmStatus = "Boot failed: \(error.localizedDescription)" }
    }

    func requestShutdown() {
        guard !vmOperationInProgress, !provisioning else { return }
        do {
            try vm.requestShutdown()
            shutdownRequested = true
            vmStatus = "Shutdown requested. Waiting for the guest; use Force stop if it does not respond."
        } catch { vmFailure = error.localizedDescription; vmStatus = "Shutdown request failed: \(error.localizedDescription)" }
    }

    func showExternalConsole() {
        guard let pid = vm.externalConsoleProcessID else { return }
        NSRunningApplication(processIdentifier: pid)?.activate(options: [])
    }

    func stopVM() async {
        guard !provisioning, !vmOperationInProgress else { return }
        vmOperationInProgress = true
        defer { vmOperationInProgress = false }
        do {
            if !vm.discardAlreadyStoppedSession() { try await vm.stop() }
            vmRevision += 1
            shutdownRequested = false
            vmStatus = "VM stopped; disk images released"
        }
        catch { vmStatus = "Stop failed: \(error.localizedDescription)" }
    }
    func refreshManagedVMs() {
        var records: [String: (url: URL, record: ManagedVMManifest)] = [:]
        for path in recentPaths {
            let folder = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath()
            if let record = try? VMRegistry.read(at: folder) { records[folder.path] = (folder, record) }
        }
        if vmFolderPath.hasPrefix("/") {
            for item in VMRegistry.discover(in: URL(fileURLWithPath: vmFolderPath).deletingLastPathComponent()) {
                let folder = item.url.standardizedFileURL.resolvingSymlinksInPath()
                records[folder.path] = (folder, item.record)
            }
        }
        knownVMs = records.values.sorted { $0.record.createdAt > $1.record.createdAt }
    }

    func provisionVM() async {
        guard !isVMInUse else { return }
        let mediaPath = guestOS == .macOS ? restoreImagePath : installationISOPath
        guard vmFolderPath.hasPrefix("/"), mediaPath.hasPrefix("/") else {
            vmStatus = "Choose a new VM folder path and local \(guestOS == .macOS ? "IPSW" : "ARM64 ISO")"; return
        }
        if guestOS == .windowsARM {
            do {
                let settings = try VMQEMUSettings.discover(qemuPath: qemuExecutablePath, swtpmPath: swtpmExecutablePath)
                guard try requestBackendApprovalIfNeeded(settings, action: .provision) else { return }
                try settings.verifyApprovedVersions(using: backendTrustStore)
            } catch { vmFailure = error.localizedDescription; vmStatus = "Backend check failed: \(error.localizedDescription)"; return }
        }
        provisioning = true
        vmFailure = nil
        hardwareLoaded = true
        installProgress = 0
        let progressMonitor = Task { @MainActor in
            while !Task.isCancelled {
                installProgress = vm.installationProgress
                try? await Task.sleep(nanoseconds: 350_000_000)
            }
        }
        vmStatus = "Preparing \(guestOS.title) installation"
        defer {
            progressMonitor.cancel(); provisioning = false; vmRevision += 1
            let folder = URL(fileURLWithPath: vmFolderPath)
            if let record = try? VMRegistry.read(at: folder) {
                selectedManifest = record; loadedFolderPath = folder.path
                loadGuestDetails(from: folder, record: record)
                savedHardware = hardware; savedConnectivity = connectivity
                recentPaths.removeAll { $0 == folder.path }; recentPaths.insert(folder.path, at: 0)
                recentPaths = Array(recentPaths.prefix(30)); preferences?.set(recentPaths, forKey: "recentVMPaths")
            }
            refreshManagedVMs()
        }
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
        } catch { vmFailure = error.localizedDescription; vmStatus = "Installation failed: \(error.localizedDescription). Incomplete VM data was retained." }
    }

    var isVMInUse: Bool { provisioning || vmOperationInProgress || vm.operationInProgress || vm.hasSession }

    private func requestBackendApprovalIfNeeded(_ settings: VMQEMUSettings, action: BackendApprovalAction) throws -> Bool {
        guard let identity = try settings.firstUnapprovedExecutable(using: backendTrustStore) else { return true }
        pendingBackendAction = action
        backendApprovalRequest = identity
        vmStatus = "Approval is required before this workspace can run its Windows backend."
        return false
    }

    func approveBackendExecutable(persistently: Bool) {
        guard let identity = backendApprovalRequest, let action = pendingBackendAction else { return }
        do {
            try backendTrustStore.approve(identity, persistently: persistently)
            backendApprovalRequest = nil; pendingBackendAction = nil
            switch action {
            case .start: Task { await bootManagedVM() }
            case .provision: Task { await provisionVM() }
            }
        } catch {
            backendApprovalRequest = nil; pendingBackendAction = nil
            vmFailure = error.localizedDescription; vmStatus = "Backend approval failed: \(error.localizedDescription)"
        }
    }

    func cancelBackendExecutableApproval() {
        backendApprovalRequest = nil; pendingBackendAction = nil
        vmStatus = "Windows VM start canceled because its backend executable was not approved."
    }

    func finishARMInstallation() {
        guard !isVMInUse else { vmStatus = "Shut down and stop the VM before finishing installation"; return }
        do {
            try vm.finishARMInstallation(at: URL(fileURLWithPath: vmFolderPath))
            loadGuestDetails(from: URL(fileURLWithPath: vmFolderPath))
            refreshManagedVMs()
            vmStatus = "Installation acknowledged; the installer ISO will be ejected on the next boot"
        } catch { vmStatus = "Could not finish installation: \(error.localizedDescription)" }
    }

    func saveARMGuestMedia() {
        guard !isVMInUse else { vmStatus = "Stop the VM before changing installation media"; return }
        guard vmFolderPath.hasPrefix("/") else { vmStatus = "Select an existing VM folder"; return }
        do {
            let folder = URL(fileURLWithPath: vmFolderPath)
            var record = try VMRegistry.read(at: folder)
            guard record.guestOS != .macOS else { throw VMGuestError.invalidState }
            let installer = installationISOPath.isEmpty ? nil : URL(fileURLWithPath: installationISOPath)
            if record.state == .installing {
                guard let installer else { throw VMGuestError.invalidISO }
                try VMGuestMedia.verifyISO(installer)
            }
            if record.guestOS == .windowsARM {
                let drivers = windowsDriverISOPath.isEmpty ? nil : URL(fileURLWithPath: windowsDriverISOPath)
                if let drivers { try VMGuestMedia.verifyISO(drivers) }
                var tools = try VMQEMUSettings.discover(qemuPath: qemuExecutablePath, swtpmPath: swtpmExecutablePath)
                tools.machine = record.qemu?.machine ?? "virt-9.2"
                record.qemu = tools
                record.driverMediaPath = drivers?.path
            }
            record.installationMediaPath = installer?.path
            try VMWorkspaceTransaction.commit(at: folder, manifest: record,
                hardware: try VMHardwareStore.load(from: folder), connectivity: try VMConnectivityStore.load(from: folder))
            selectedManifest = record
            refreshManagedVMs()
            vmStatus = "Saved ARM media and executable paths for the next boot"
        } catch { vmStatus = "Media update failed: \(error.localizedDescription)" }
    }

    func canBeginQuit() -> Bool {
        guard !provisioning, !vmOperationInProgress, !vm.operationInProgress, !transferInProgress else {
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
            try VMWorkspaceTransaction.commit(at: folder, manifest: try VMRegistry.read(at: folder),
                hardware: saved, connectivity: try VMConnectivityStore.load(from: folder))
            savedHardware = saved
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
            diskImageStatus = asBootDisk ? "Boot image selected. Keep the original VM identity and firmware files when running an existing installation." : "Secondary image attached for the next boot"
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

    func setDiskReadOnly(_ disk: VMAdditionalDisk, _ readOnly: Bool) {
        do {
            try updateDiskSelection { settings in
                if let index = settings.additionalDisks.firstIndex(where: { $0.id == disk.id }) {
                    settings.additionalDisks[index].readOnly = readOnly
                }
            }
            diskImageStatus = "Disk access saved for the next boot"
        } catch { diskImageStatus = "Access update failed: \(error.localizedDescription)" }
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
                if loadedFolderPath == folder.path { selectedManifest = manifest }
                refreshManagedVMs()
            }
            diskImageStatus = "Image grown to \(sizeGiB) GiB. Expand the partition and filesystem inside the guest to use the new space."
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
