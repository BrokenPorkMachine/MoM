import SwiftUI
import AppKit

struct DashboardView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedTab = 1
    private let initialWorkspaceSection: VMWorkspaceSection

    init(initialWorkspaceSection: VMWorkspaceSection = .overview) {
        self.initialWorkspaceSection = initialWorkspaceSection
    }

    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "square.stack.3d.up.fill").font(.title2).foregroundStyle(
                        LinearGradient(colors: [Color.accentColor, Color.cyan], startPoint: .topLeading, endPoint: .bottomTrailing))
                    VStack(alignment: .leading, spacing: 3) {
                        Text("MoM: MacOnMac").font(.headline.weight(.bold))
                        Text("Virtual machine studio").font(.caption).foregroundStyle(.secondary)
                    }
                }.foregroundColor(sidebarForeground).padding(20)
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        sidebarGroup("Workspace") {
                            sidebarItem("Virtual machines", symbol: "desktopcomputer", tab: 1)
                            sidebarItem("Network & guest tools", symbol: "network", tab: 4)
                        }
                        sidebarGroup("Host storage") {
                            sidebarItem("Storage inventory", symbol: "externaldrive", tab: 0)
                            sidebarItem("macOS installations", symbol: "internaldrive", tab: 3)
                        }
                        sidebarGroup("Advanced") { sidebarItem("Research", symbol: "testtube.2", tab: 2) }
                    }.padding(.horizontal, 12).padding(.vertical, 16)
                }
                Divider()
                VStack(alignment: .leading, spacing: 7) {
                    Label("Apple Silicon · ARM64", systemImage: "cpu").font(.caption.weight(.medium))
                    Text("Local virtualization").font(.caption).foregroundStyle(.secondary)
                }.foregroundColor(sidebarForeground).padding(20)
            }
            .background(.ultraThinMaterial)
            .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 280)
        } detail: {
            Group {
                switch selectedTab {
                case 1: managedVM
                case 3: installationsView
                case 4: connectivityView
                case 2: research
                default: ScrollView { inventory }
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color(nsColor: .windowBackgroundColor))
            .toolbar {
                ToolbarItemGroup {
                    Button {
                        if WorkspaceActions.allowDiscard(model) { model.beginNewVM(); selectedTab = 1 }
                    } label: { Label("New VM", systemImage: "plus") }
                    .disabled(!model.canSelectVM).help("Create a virtual machine")
                    Button {
                        WorkspaceActions.openVM(model); selectedTab = 1
                    } label: { Label("Open VM", systemImage: "folder") }
                    .disabled(!model.canSelectVM).help("Open an existing VM folder")
                }
            }
        }
        .task {
            model.refreshNetworkInterfaces()
        }
        .task(id: selectedTab) {
            if (selectedTab == 0 || selectedTab == 3) && model.devices.isEmpty { await model.scan() }
        }
        .onChange(of: model.workspaceRevision) { _, _ in selectedTab = 1 }
    }

    private func sidebarGroup<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.caption.weight(.semibold)).foregroundColor(sidebarForeground.opacity(0.7)).padding(.horizontal, 8)
            content()
        }
    }

    private func sidebarItem(_ title: String, symbol: String, tab: Int) -> some View {
        Button { selectedTab = tab } label: {
            Label(title, systemImage: symbol)
                .font(.callout.weight(selectedTab == tab ? .semibold : .regular))
                .foregroundColor(selectedTab == tab ? Color(red: 0.15, green: 0.5, blue: 0.98) : sidebarForeground)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 10).padding(.vertical, 11)
                .background(selectedTab == tab ? Color.blue.opacity(0.13) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
                .contentShape(Rectangle())
        }.buttonStyle(.plain)
            .accessibilityAddTraits(selectedTab == tab ? [.isSelected] : [])
    }

    private var sidebarForeground: Color { Color(white: colorScheme == .dark ? 0.9 : 0.12) }

    private var inventory: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Storage inventory").font(.system(.title2, design: .rounded).weight(.bold))
                    Text("A live view of disks and APFS volumes on this Mac.").font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Button { Task { await model.scan() } } label: {
                    Label(model.scanInProgress ? "Scanning" : "Refresh", systemImage: model.scanInProgress ? "arrow.trianglehead.2.clockwise" : "arrow.clockwise")
                }.buttonStyle(.bordered).disabled(model.scanInProgress)
            }
            if model.scanInProgress {
                HStack(spacing: 12) {
                    ProgressView().controlSize(.small)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Prioritized parallel scan").font(.callout.weight(.semibold))
                        Text("Querying host storage and APFS together with bounded workers.").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                }.padding(13).background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            HStack(spacing: 10) {
                Label(model.status, systemImage: "externaldrive").foregroundStyle(.secondary)
                Text("·").foregroundStyle(.tertiary)
                Label(model.apfsStatus, systemImage: "square.stack.3d.up").foregroundStyle(.secondary)
            }.font(.caption)
            Table(model.devices, selection: $model.selectedDeviceID) {
                TableColumn("Device", value: \.identifier)
                TableColumn("Name", value: \.name)
                TableColumn("Filesystem", value: \.filesystem)
                TableColumn("Mount", value: \.mountPoint)
            }
            .frame(minHeight: 240, idealHeight: 300)
            .overlay {
                if model.devices.isEmpty {
                    ContentUnavailableView(model.scanInProgress ? "Scanning storage" : "No storage records", systemImage: "externaldrive",
                        description: Text(model.scanInProgress ? "Reading the host storage inventory…" : model.status))
                }
            }
            if let selected = model.devices.first(where: { $0.id == model.selectedDeviceID }) {
                let verdict = model.inspect(selected)
                GroupBox("Selected device") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Transport: \(selected.transport)")
                        Text("Whole disk: \(selected.isWholeDisk ? "yes" : "no")")
                        Text("Status: \(verdict.status.rawValue)")
                        ForEach(model.apfsVolumes(for: selected)) { volume in
                            Text("APFS: \(volume.name) — roles: \(volume.roles.joined(separator: ", "))")
                        }
                        ForEach(verdict.reasons, id: \.self) { Text("• \($0)") }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            DisclosureGroup("Physical device diagnostics") {
                VStack(alignment: .leading, spacing: 8) {
                    Text(model.diskPreflightStatus).font(.caption).textSelection(.enabled)
                    Button("Check selected device") { Task { await model.checkSelectedPhysicalDevice() } }
                        .disabled(model.selectedDeviceID == nil || model.diskPreflightRunning)
                    HStack {
                        Button("Check XPC service") { Task { await model.checkDiskBroker() } }
                            .disabled(model.brokerDiagnosticRunning)
                        Text(model.brokerDiagnostic).font(.caption).textSelection(.enabled)
                    }
                    Text("Host disk inventory and topology are inspection-only. Physical disk handles are disabled in this release.")
                        .font(.caption).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            DisclosureGroup("Privileged service administration") {
                VStack(alignment: .leading, spacing: 8) {
                    Text(model.privilegedDaemonStatus).font(.caption).textSelection(.enabled)
                    Text(model.privilegedDaemonDiagnostic).font(.caption).textSelection(.enabled)
                    HStack {
                        Button("Check registration") { model.refreshPrivilegedDaemonStatus() }
                        Button("Request installation") { model.registerPrivilegedDaemon() }
                        Button("Approval settings") { model.openPrivilegedDaemonApproval() }
                        Button("Test signed connection") { Task { await model.checkPrivilegedDaemon() } }
                            .disabled(model.privilegedDaemonBusy)
                    }
                    Button("Inspect selected disk topology (no writes)") {
                        Task { await model.inspectSelectedDaemonTopology() }
                    }.disabled(model.selectedDeviceID == nil || model.detailedTopologyBusy)
                    Text(model.detailedTopologyStatus).font(.caption).textSelection(.enabled)
                    Text("A signed daemon may provide read-only topology diagnostics. Physical disk grants are disabled in this release, regardless of daemon registration or administrator approval.")
                        .font(.caption).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            if !model.topology.warnings.isEmpty {
                Text(model.topology.warnings.joined(separator: "; ")).font(.caption).foregroundStyle(.orange)
            }
            Text("Physical disk attachment is disabled in this release. Existing macOS installations cannot be attached or booted.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var installationsView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("macOS installations").font(.title2.bold())
                Spacer()
                Button("Rescan") { Task { await model.scan() } }.disabled(model.scanInProgress)
            }
            Text("System-role APFS volumes only. A detected candidate is not a verified bootable installation.")
                .foregroundStyle(.secondary)
            List(model.installations) { candidate in
                VStack(alignment: .leading, spacing: 5) {
                    Text(candidate.systemName).font(.headline)
                    Text("System: \(candidate.systemDevice) · Data: \(candidate.dataDevice ?? "unverified")")
                    Text("Volume group: \(candidate.groupUUID ?? "unknown")").font(.caption)
                    ForEach(candidate.warnings, id: \.self) { warning in
                        Text("• \(warning)").font(.caption).foregroundStyle(.secondary)
                    }
                }.padding(.vertical, 4)
            }
        }
    }

    private var managedVM: some View {
        VMWorkspaceView(hardware: hardwareConfiguration, network: connectivityView, initialSection: initialWorkspaceSection)
    }

    private var hardwareConfiguration: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Instance hardware").font(.title2.bold())
                        Text("Allocate resources and configure the guest. Saved changes apply at the next start.")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Menu("Presets") {
                        Button("Balanced · 4 cores / 8 GiB") { applyHardwarePreset(cpu: 4, memory: 8) }
                        Button("Performance · 8 cores / 16 GiB") { applyHardwarePreset(cpu: 8, memory: 16) }
                        Button("Lightweight · 2 cores / 4 GiB") { applyHardwarePreset(cpu: 2, memory: 4) }
                    }
                }
                HStack {
                    Text(model.vmFolderPath.isEmpty ? "New workspace" : model.vmFolderPath)
                        .font(.callout.monospaced()).lineLimit(1).truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
                    Button("Reload saved profile…") { if WorkspaceActions.allowDiscard(model) { model.loadConnectivity() } }.disabled(!model.canSelectVM || model.currentManifest == nil)
                        .disabled(model.vmFolderPath.isEmpty)
                }
                HStack(spacing: 12) {
                    metricCard("PROCESSING", value: "\(model.hardware.cpuCount) cores", icon: "cpu.fill", tint: .blue)
                    metricCard("MEMORY", value: "\(model.hardware.memoryGiB) GiB", icon: "memorychip.fill", tint: .purple)
                    metricCard("DISPLAY", value: model.hardware.display.title, icon: "display", tint: .orange)
                }
                GroupBox {
                    VStack(alignment: .leading, spacing: 16) {
                        sectionHeading("Identity", subtitle: "A friendly name for this VM instance")
                        TextField("For example, Development VM", text: $model.hardware.displayName)
                            .textFieldStyle(.roundedBorder)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(4)
                }
                GroupBox {
                    VStack(alignment: .leading, spacing: 16) {
                        sectionHeading("Compute", subtitle: "Choose how much of your Mac to share with the guest")
                        HStack(spacing: 24) {
                            VStack(alignment: .leading, spacing: 9) {
                                Label("Virtual CPU", systemImage: "cpu")
                                Stepper("\(model.hardware.cpuCount) cores", value: $model.hardware.cpuCount, in: 2...model.maximumCPUCount, step: 1)
                                Text("Host has \(ProcessInfo.processInfo.processorCount) logical cores").font(.caption).foregroundStyle(.secondary)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                            VStack(alignment: .leading, spacing: 9) {
                                Label("Memory", systemImage: "memorychip")
                                Stepper("\(model.hardware.memoryGiB) GiB", value: $model.hardware.memoryGiB, in: 4...model.safeMaximumMemoryGiB, step: 2)
                                Text("Leave room for macOS and other apps").font(.caption).foregroundStyle(.secondary)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(4)
                }
                GroupBox {
                    VStack(alignment: .leading, spacing: 14) {
                        sectionHeading("Display", subtitle: "Set the guest’s starting resolution")
                        Label(model.guestOS == .macOS ? "Apple virtual Mac display · host accelerated where supported" :
                              model.guestOS == .linuxARM ? "VirtIO guest display" : "QEMU framebuffer · resolution selected by guest firmware", systemImage: "sparkles")
                            .font(.caption).foregroundStyle(.secondary)
                        Picker("Resolution", selection: $model.hardware.display) {
                            ForEach(VMDisplayPreset.allCases) { preset in Text(preset.title).tag(preset) }
                        }.pickerStyle(.segmented).disabled(model.guestOS == .windowsARM)
                        Toggle("Resize guest display with the VM window", isOn: $model.hardware.automaticallyResizeDisplay)
                            .disabled(model.guestOS == .windowsARM)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(4)
                }
                GroupBox {
                    VStack(alignment: .leading, spacing: 13) {
                        sectionHeading("Sound", subtitle: "Virtual audio devices presented to the guest")
                        Toggle("Audio output", isOn: $model.hardware.audioOutputEnabled)
                        Toggle("Microphone input", isOn: $model.hardware.microphoneEnabled)
                            .disabled(!model.hardware.audioOutputEnabled || model.guestOS == .windowsARM)
                        if model.hardware.microphoneEnabled {
                            Label("The guest may request microphone access from macOS.", systemImage: "mic.badge.waveform")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(4)
                }
                DisclosureGroup("Host device access") {
                    VStack(alignment: .leading, spacing: 13) {
                        sectionHeading("Device passthrough", subtitle: "Virtual devices provide guest access to supported host resources")
                        Label("Apple Neural Engine passthrough is not exposed by Virtualization.framework. Guests cannot claim the host ANE directly.", systemImage: "cpu")
                            .font(.callout).foregroundStyle(.secondary)
                        Label("Physical GPU passthrough is not available for macOS guests. Apple’s Mac graphics device is managed by the host virtualization framework.", systemImage: "display")
                            .font(.callout).foregroundStyle(.secondary)
                        Label("Direct USB accessory passthrough is unavailable in this release.", systemImage: "cable.connector")
                            .font(.callout).foregroundStyle(.secondary)
                        Divider()
                        Label("Physical disk attachment is disabled in this release.", systemImage: "externaldrive.badge.xmark")
                        Text("Host disk inventory and topology diagnostics are inspection-only. Use managed VM disk images for guest storage.")
                            .font(.caption).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(4)
                }
                GroupBox {
                    VStack(alignment: .leading, spacing: 13) {
                        sectionHeading("Input", subtitle: "Choose how keyboard and pointer input appears to the guest")
                        Picker("Keyboard", selection: $model.hardware.keyboard) {
                            ForEach(VMKeyboardKind.allCases.filter { model.guestOS == .macOS || $0 == .usb }) { kind in Text(kind.title).tag(kind) }
                        }
                        Picker("Pointing device", selection: $model.hardware.pointer) {
                            ForEach(VMPointerKind.allCases.filter { model.guestOS == .macOS || $0 == .mouse }) { kind in Text(kind.title).tag(kind) }
                        }
                        Toggle("Capture system shortcuts in the VM", isOn: $model.hardware.capturesSystemKeys)
                            .disabled(model.guestOS == .windowsARM)
                        Toggle("Capture mouse when clicking the guest console", isOn: $model.hardware.capturesMouseOnClick)
                            .disabled(model.guestOS == .windowsARM)
                        Picker("Release mouse and keyboard", selection: $model.hardware.inputReleaseShortcut) {
                            ForEach(VMInputReleaseShortcut.allCases) { Text($0.title).tag($0) }
                        }
                        .disabled(model.guestOS == .windowsARM)
                        if model.guestOS == .windowsARM {
                            Text("The QEMU window uses Control + Option + G to capture/release input.").font(.caption)
                        }
                        Text(model.guestOS == .windowsARM ? "Use QEMU’s window controls for mouse capture and release." :
                             "The release hotkey always stays on the host. Input also releases when the app or VM window loses focus.")
                            .font(.caption).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(4)
                }
                GroupBox {
                    VStack(alignment: .leading, spacing: 13) {
                        HStack {
                            sectionHeading("Additional disk images", subtitle: "Attach .img or .raw files as writable secondary drives")
                            Spacer()
                            Button { addHardwareDisk() } label: { Label("Add disk", systemImage: "plus") }
                        }
                        if model.hardware.additionalDisks.isEmpty {
                            ContentUnavailableView("No extra disks", systemImage: "externaldrive", description: Text("The VM’s main disk is always attached automatically."))
                                .frame(height: 100)
                        } else {
                            ForEach(model.hardware.additionalDisks) { disk in
                                HStack(spacing: 12) {
                                    Image(systemName: "externaldrive.fill").foregroundStyle(.blue)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(URL(fileURLWithPath: disk.path).lastPathComponent).font(.subheadline.weight(.medium))
                                        Text(disk.path).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                                    }
                                    Spacer()
                                    Toggle("Read only", isOn: Binding(get: { disk.readOnly }, set: { model.setDiskReadOnly(disk, $0) })).toggleStyle(.switch)
                                    Button { model.detachDiskImage(disk) } label: {
                                        Image(systemName: "minus.circle")
                                    }.buttonStyle(.borderless)
                                        .help("Detach image without deleting the file")
                                }.padding(10).background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 10))
                            }
                        }
                        Text("Disk images only. Raw device paths and files inside the VM bundle are rejected.")
                            .font(.caption).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(4)
                }
                HStack {
                    Image(systemName: model.hardwareLoaded ? "checkmark.circle.fill" : "info.circle.fill")
                        .foregroundStyle(model.hardwareLoaded ? .green : .secondary)
                    Text(model.hardwareStatus).font(.callout).foregroundStyle(.secondary)
                    Spacer()
                    Button("Save hardware") { model.saveHardware() }
                        .buttonStyle(.borderedProminent)
                        .disabled(model.currentManifest == nil || !model.hasUnsavedHardware || model.isVMInUse)
                }.padding(.vertical, 4)
                Text("Hardware changes apply on the next VM start. Provisioning uses the current hardware profile; after installation, each instance has its own saved profile.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(.bottom, 12)
            .disabled(model.isVMInUse)
        }
    }

    private func applyHardwarePreset(cpu: Int, memory: Int) {
        model.hardware.cpuCount = min(cpu, model.maximumCPUCount)
        model.hardware.memoryGiB = min(memory, model.safeMaximumMemoryGiB)
    }

    private func metricCard(_ title: String, value: String, icon: String, tint: Color) -> some View {
        WorkspaceMetric(title: title.capitalized, value: value, symbol: icon)
    }

    private func sectionHeading(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.headline)
            Text(subtitle).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func addHardwareDisk() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.init(filenameExtension: "img")!, .init(filenameExtension: "raw")!]
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            model.selectDiskImage(url, asBootDisk: false)
        }
    }

    private var connectivityView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Network & guest tools").font(.title2.bold())
                Text("Network settings and shared directories belong to a specific managed VM. Changes take effect on next boot.")
                    .foregroundStyle(.secondary)
                HStack {
                    Text(model.vmFolderPath.isEmpty ? "Choose a workspace" : model.vmFolderPath).font(.callout.monospaced()).lineLimit(1).truncationMode(.middle)
                    Button("Reload saved profile…") { if WorkspaceActions.allowDiscard(model) { model.loadConnectivity() } }.disabled(!model.canSelectVM || model.currentManifest == nil)
                    Button("Save network") { model.saveConnectivity() }.disabled(model.currentManifest == nil || !model.hasUnsavedConnectivity || model.isVMInUse)
                }
                Text(model.connectivityStatus).font(.caption).foregroundStyle(.secondary)
                GroupBox("Guest networking") {
                    VStack(alignment: .leading, spacing: 12) {
                        Picker("Network mode", selection: $model.connectivity.networkMode) {
                            Text("NAT — internet through host (default)").tag(VMNetworkMode.nat)
                            Text("Disconnected").tag(VMNetworkMode.disconnected)
                        }
                        Text("NAT gives guests outbound connectivity. It does not automatically make guest services reachable from the LAN.")
                            .font(.caption).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.disabled(model.isVMInUse)
                GroupBox("Host workspace share — VirtioFS") {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            TextField("Optional host folder", text: Binding(
                                get: { model.connectivity.sharedFolderPath ?? "" },
                                set: { model.connectivity.sharedFolderPath = $0.isEmpty ? nil : $0 }))
                            Button("Choose…") {
                                let panel = NSOpenPanel()
                                panel.canChooseDirectories = true
                                panel.canChooseFiles = false
                                if panel.runModal() == .OK { model.connectivity.sharedFolderPath = panel.url?.path }
                            }
                            Button("Clear") { model.connectivity.sharedFolderPath = nil }
                        }
                        Toggle("Share workspace read-only (recommended)", isOn: $model.connectivity.shareReadOnly)
                        Text(model.guestOS == .linuxARM ? "Mount the volumeboot VirtIO filesystem inside Linux to access Workspace. A VM bundle or ancestor directory is not an eligible share." :
                             model.guestOS == .windowsARM ? "Workspace sharing is unavailable for this Windows backend." :
                             "macOS guests automatically mount shares under /Volumes/My Shared Files/. A VM bundle or ancestor directory is not an eligible share.")
                            .font(.caption).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.disabled(model.guestOS == .windowsARM || model.isVMInUse)
                GroupBox("Guest companion tools") {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("Enable explicit host–guest exchange", isOn: $model.connectivity.guestToolsEnabled).disabled(model.isVMInUse)
                        Text("The guest receives a separate read/write Exchange folder. This data-only channel never executes received messages or scripts.")
                            .font(.caption).foregroundStyle(.secondary)
                        HStack {
                            TextField("Message to guest", text: $model.outgoingMessage)
                            Button("Send") { model.sendHostMessage() }
                                .disabled(!model.connectivity.guestToolsEnabled || model.outgoingMessage.isEmpty)
                        }
                        HStack {
                            Button("Stage a file for guest") {
                                let panel = NSOpenPanel()
                                panel.canChooseDirectories = false
                                panel.canChooseFiles = true
                                if panel.runModal() == .OK, let url = panel.url { model.sendHostFile(url) }
                            }.disabled(!model.connectivity.guestToolsEnabled)
                            Button("Refresh guest status") { model.refreshExchange() }
                            Button("Open exchange in Finder") {
                                guard model.vmFolderPath.hasPrefix("/") else { return }
                                NSWorkspace.shared.open(HostGuestExchange.root(for: URL(fileURLWithPath: model.vmFolderPath)))
                            }
                        }
                        if model.transferInProgress {
                            ProgressView(value: model.transferProgress) {
                                Text("File transfer")
                            } currentValueLabel: {
                                Text("\(Int(model.transferProgress * 100))%")
                            }
                        }
                        Text(model.exchangeStatus).font(.caption).foregroundStyle(.secondary)
                        if !model.guestTransfers.isEmpty {
                            Text("Verified files from guest").font(.headline)
                            ForEach(model.guestTransfers) { transfer in
                                HStack {
                                    Text("\(transfer.receipt.originalName) · \(transfer.receipt.bytes) bytes")
                                        .font(.caption).lineLimit(1)
                                    Spacer()
                                    Button("Save…") {
                                        let panel = NSOpenPanel()
                                        panel.canChooseDirectories = true
                                        panel.canChooseFiles = false
                                        panel.canCreateDirectories = true
                                        if panel.runModal() == .OK, let folder = panel.url {
                                            model.receiveGuestTransfer(transfer, destination: folder)
                                        }
                                    }
                                }
                            }
                        }
                        Divider()
                        Text("Manual text clipboard").font(.headline)
                        HStack {
                            Button("Offer host clipboard to guest") { model.sendHostClipboard() }
                            Button("Import guest clipboard to host") { model.importGuestClipboard() }
                        }.disabled(!model.connectivity.guestToolsEnabled)
                        Text(model.clipboardStatus).font(.caption).foregroundStyle(.secondary)
                        Text("Only plain text; no automatic clipboard observation or import.")
                            .font(.caption).foregroundStyle(.secondary)
                        Divider()
                        Text("Paired guest diagnostics").font(.headline)
                        HStack {
                            Button("Show pairing code") { model.showGuestPairingCode() }
                            Button("Send authenticated ping") { model.queueAuthenticatedGuestPing() }
                                .disabled(!model.connectivity.guestToolsEnabled)
                            Button("Refresh") { model.refreshExchange() }
                        }
                        if !model.pairingCode.isEmpty {
                            Text(model.pairingCode).font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                        }
                        Text(model.authenticatedStatus).font(.caption).foregroundStyle(.secondary)
                        Text(model.networkHealth).font(.caption).foregroundStyle(.secondary)
                        if let heartbeat = model.guestHeartbeat {
                            Text("Guest: \(heartbeat.hostname) · \(heartbeat.operatingSystem) · last heartbeat \(heartbeat.timestamp.formatted())")
                                .font(.caption)
                        } else {
                            Text("No guest heartbeat received. Install and run the bundled guest agent inside the VM.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        ForEach(model.guestMessages) { entry in
                            Text("[\(entry.timestamp.formatted())] \(entry.body)")
                                .font(.caption).textSelection(.enabled)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.disabled(model.guestOS != .macOS)
                Text(model.guestOS == .macOS ? "Compile the guest agent using Scripts/build-guest-agent.sh. Run Scripts/install-guest-agent.sh inside the guest to opt in to automatic login startup. No remote shell is provided." :
                     "The bundled companion tools run in macOS guests. Linux can use the workspace share directly.")
                    .font(.caption).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var research: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Research laboratory").font(.title2.bold())
            Text("No physical macOS installation boot or boot-policy modification is performed by this build. Physical disk attachment is disabled in this release.")
            Text("See Docs/EXPERIMENTS.md for controlled, non-destructive test procedures.")
                .foregroundStyle(.secondary)
        }
    }
}
