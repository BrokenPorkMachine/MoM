import SwiftUI
import AppKit

struct DashboardView: View {
    @EnvironmentObject private var model: AppModel
    @State private var selectedTab = 0

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedTab) {
                Label("Storage inventory", systemImage: "externaldrive").tag(0)
                Label("Installations", systemImage: "internaldrive").tag(3)
                Label("Managed VM", systemImage: "desktopcomputer").tag(1)
                Label("Network & Guest Tools", systemImage: "network").tag(4)
                Label("Research laboratory", systemImage: "testtube.2").tag(2)
            }
            .navigationTitle("VolumeBoot")
            .listStyle(.sidebar)
        } detail: {
            Group {
                switch selectedTab {
                case 1: managedVM
                case 3: installationsView
                case 4: connectivityView
                case 2: research
                default: inventory
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .task {
            model.refreshNetworkInterfaces()
            await model.scan()
        }
    }

    private var inventory: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Local storage").font(.largeTitle.bold())
                Spacer()
                Button("Rescan") { Task { await model.scan() } }.disabled(model.scanInProgress)
            }
            Text(model.status).foregroundStyle(.secondary)
            Text(model.apfsStatus).font(.subheadline).foregroundStyle(.secondary)
            Table(model.devices, selection: $model.selectedDeviceID) {
                TableColumn("Device", value: \.identifier)
                TableColumn("Name", value: \.name)
                TableColumn("Filesystem", value: \.filesystem)
                TableColumn("Mount", value: \.mountPoint)
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
            GroupBox("Physical device preflight (read-only)") {
                VStack(alignment: .leading, spacing: 8) {
                    Text(model.diskPreflightStatus).font(.caption).textSelection(.enabled)
                    Button("Check selected device") { Task { await model.checkSelectedPhysicalDevice() } }
                        .disabled(model.selectedDeviceID == nil || model.diskPreflightRunning)
                    HStack {
                        Button("Check XPC service") { Task { await model.checkDiskBroker() } }
                            .disabled(model.brokerDiagnosticRunning)
                        Text(model.brokerDiagnostic).font(.caption).textSelection(.enabled)
                    }
                    Text("Read-only advisory analysis only. No physical disk handles are granted by the current unprivileged XPC service.")
                        .font(.caption).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            GroupBox("Privileged daemon — signed deployment") {
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
                    Text("Requires signed daemon and administrator approval. Read-only grants remain limited to blank external scratch disks; partitioned/APFS disks are inspection-only until exclusive claiming is validated.")
                        .font(.caption).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            if !model.topology.warnings.isEmpty {
                Text(model.topology.warnings.joined(separator: "; ")).font(.caption).foregroundStyle(.orange)
            }
            Text("Physical attachment is experimental and limited to blank disposable external media. Never select a disk with data you need; no direct boot of existing macOS installations.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var installationsView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("macOS installation candidates").font(.largeTitle.bold())
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
        VStack(alignment: .leading, spacing: 16) {
            Text("Managed virtual machine").font(.largeTitle.bold())
            Text("Create a managed macOS guest from an Apple IPSW restore image, or start a previously installed VM.")
                .foregroundStyle(.secondary)
            HStack {
                TextField("VM bundle folder", text: $model.vmFolderPath)
                Button("Choose…") {
                    let panel = NSOpenPanel()
                    panel.canChooseDirectories = true
                    panel.canChooseFiles = false
                    if panel.runModal() == .OK { model.vmFolderPath = panel.url?.path ?? "" }
                }
            }
            HStack {
                TextField("Apple macOS restore image (.ipsw)", text: $model.restoreImagePath)
                Button("Choose IPSW…") {
                    let panel = NSOpenPanel()
                    panel.allowedContentTypes = [.init(filenameExtension: "ipsw")!]
                    panel.canChooseDirectories = false
                    panel.canChooseFiles = true
                    if panel.runModal() == .OK { model.restoreImagePath = panel.url?.path ?? "" }
                }
            }
            Stepper("Virtual disk: \(model.diskSizeGiB) GiB", value: $model.diskSizeGiB, in: 64...512, step: 16)
            Stepper("Virtual CPUs: \(model.cpuCount)", value: $model.cpuCount, in: 2...8)
            Stepper("Memory: \(model.memoryGiB) GiB", value: $model.memoryGiB, in: 2...16)
            Toggle("Attach selected BLANK external disk as read-only secondary storage", isOn: $model.attachDisposableDisk)
            Text("Requires signed and approved root daemon. Only disposable, unmounted, unpartitioned external disks are accepted. The selected physical disk is NEVER the VM boot disk.")
                .font(.caption).foregroundStyle(.orange)
            HStack {
                Button("Install macOS") { Task { await model.provisionVM() } }
                    .disabled(model.provisioning || model.vmFolderPath.isEmpty || model.restoreImagePath.isEmpty)
                Button("Start VM") { Task { await model.bootManagedVM() } }
                    .disabled(model.provisioning || model.vmFolderPath.isEmpty)
                Button("Stop") { Task { await model.stopVM() } }.disabled(model.provisioning)
            }
            if model.provisioning {
                ProgressView(value: min(max(model.installProgress, 0), 1)) {
                    Text("Installing macOS")
                } currentValueLabel: {
                    Text("\(Int(model.installProgress * 100))%")
                }
            }
            Text(model.vmStatus).foregroundStyle(.secondary)
            GroupBox("Detected managed VMs") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("VM records in destination parent folder")
                        Spacer()
                        Button("Refresh") { model.refreshManagedVMs() }
                    }
                    ForEach(model.knownVMs, id: \.record.id) { entry in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(entry.url.lastPathComponent).font(.headline)
                                Text(entry.record.state.rawValue).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Select") { model.vmFolderPath = entry.url.path; model.loadConnectivity() }
                        }
                    }
                }
            }
            GroupBox("Guest console") {
                VMConsoleView(virtualMachine: model.vm.virtualMachine)
                    .id(model.vmRevision)
                    .frame(minWidth: 550, minHeight: 300)
            }
            Text("Installation requires a NEW destination folder (must not already exist), compatible Apple IPSW, and sufficient disk space. Failures retain incomplete VM data; never select a physical disk device path.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var connectivityView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Network & Guest Integration").font(.largeTitle.bold())
                Text("Network settings and shared directories belong to a specific managed VM. Changes take effect on next boot.")
                    .foregroundStyle(.secondary)
                HStack {
                    TextField("Installed VM folder", text: $model.vmFolderPath)
                    Button("Load profile") { model.loadConnectivity() }
                    Button("Save profile") { model.saveConnectivity() }
                }
                Text(model.connectivityStatus).font(.caption).foregroundStyle(.secondary)
                GroupBox("Guest networking") {
                    VStack(alignment: .leading, spacing: 12) {
                        Picker("Network mode", selection: $model.connectivity.networkMode) {
                            Text("NAT — internet through host (default)").tag(VMNetworkMode.nat)
                            Text("Bridged — visible on LAN").tag(VMNetworkMode.bridged)
                            Text("Disconnected").tag(VMNetworkMode.disconnected)
                        }
                        if model.connectivity.networkMode == .bridged {
                            HStack {
                                Picker("Physical interface", selection: Binding(
                                    get: { model.connectivity.bridgedInterfaceID ?? "" },
                                    set: { model.connectivity.bridgedInterfaceID = $0 })) {
                                    Text("Select interface").tag("")
                                    ForEach(model.networkInterfaces, id: \.self) { name in Text(name).tag(name) }
                                }
                                Button("Refresh") { model.refreshNetworkInterfaces() }
                            }
                            Text("Bridging requires Apple's com.apple.vm.networking entitlement and compatible host interfaces. Standard signing may reject this mode.")
                                .font(.caption).foregroundStyle(.orange)
                        }
                        Text("NAT gives guests outbound connectivity. It does not automatically make guest services reachable from the LAN.")
                            .font(.caption).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
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
                        Text("macOS guests automatically mount shares under /Volumes/My Shared Files/. A VM bundle or ancestor directory is not an eligible share.")
                            .font(.caption).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
                GroupBox("Guest companion tools") {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("Enable explicit host–guest exchange", isOn: $model.connectivity.guestToolsEnabled)
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
                }
                Text("Compile the guest agent using Scripts/build-guest-agent.sh. Run Scripts/install-guest-agent.sh inside the guest to opt in to automatic login startup. No remote shell is provided.")
                    .font(.caption).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var research: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Boot research laboratory").font(.largeTitle.bold())
            Text("No physical macOS installation boot or boot-policy modification is performed by this build. Blank external test-disk attachment is experimental.")
            Text("See Docs/EXPERIMENTS.md for controlled, non-destructive test procedures.")
                .foregroundStyle(.secondary)
        }
    }
}
