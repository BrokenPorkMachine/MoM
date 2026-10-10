import SwiftUI
import AppKit

struct DashboardView: View {
    @EnvironmentObject private var model: AppModel
    @State private var selectedTab = 0
    @State private var selectedVMSection = 0

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
            HStack {
                VStack(alignment: .leading, spacing: 7) {
                    Text("Managed virtual machine").font(.largeTitle.bold())
                    Text("Install and run macOS, ARM Linux, or Windows ARM.").foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "cpu.fill").font(.system(size: 34)).foregroundStyle(.blue.gradient)
                    .padding(18).background(.blue.opacity(0.09), in: RoundedRectangle(cornerRadius: 18))
            }
            Picker("VM workspace", selection: $selectedVMSection) {
                Text("Overview").tag(0)
                Text("Hardware").tag(1)
                Text("Disks").tag(2)
            }.pickerStyle(.segmented).frame(maxWidth: 320)
            if selectedVMSection == 0 { vmOverview }
            else if selectedVMSection == 1 { hardwareConfiguration }
            else { VMDiskImagesView() }
        }
    }

    private var vmOverview: some View {
        VStack(alignment: .leading, spacing: 16) {
            Picker("Guest operating system", selection: $model.guestOS) {
                ForEach(VMGuestOS.allCases) { Text($0.title).tag($0) }
            }.disabled(model.isVMInUse)
                .onChange(of: model.guestOS) { _, guest in
                    if guest != .macOS { model.hardware.keyboard = .usb; model.hardware.pointer = .mouse }
                    if guest == .windowsARM {
                        model.attachDisposableDisk = false
                        model.hardware.microphoneEnabled = false
                        model.connectivity.guestToolsEnabled = false
                        model.connectivity.sharedFolderPath = nil
                        if model.connectivity.networkMode == .bridged { model.connectivity.networkMode = .nat }
                    }
                }
            HStack {
                TextField("VM bundle folder", text: $model.vmFolderPath)
                Button("Choose…") {
                    let panel = NSOpenPanel()
                    panel.canChooseDirectories = true
                    panel.canChooseFiles = false
                    if panel.runModal() == .OK, let url = panel.url { model.loadHardwareProfile(for: url) }
                }
            }.disabled(model.isVMInUse)
            installationMediaControls.disabled(model.isVMInUse)
            Stepper("New boot disk: \(model.diskSizeGiB) GiB", value: $model.diskSizeGiB, in: 64...2048, step: 16)
                .disabled(model.isVMInUse || model.hardware.bootDiskPath != nil)
            if let path = model.hardware.bootDiskPath {
                Text("Installation target: \(path)").font(.caption).textSelection(.enabled)
            }
            Button("Manage disk images") { selectedVMSection = 2 }
            HStack(spacing: 12) {
                Label("\(model.hardware.cpuCount) CPU cores", systemImage: "cpu")
                Label("\(model.hardware.memoryGiB) GiB memory", systemImage: "memorychip")
                Label(model.hardware.display.title, systemImage: "display")
            }.font(.subheadline).foregroundStyle(.secondary)
            Toggle("Attach selected BLANK external disk as read-only secondary storage", isOn: $model.attachDisposableDisk)
                .disabled(model.guestOS == .windowsARM || model.isVMInUse)
            Text("Requires signed and approved root daemon. Only disposable, unmounted, unpartitioned external disks are accepted. The selected physical disk is NEVER the VM boot disk.")
                .font(.caption).foregroundStyle(.orange)
            HStack {
                Button(model.guestOS == .macOS ? "Install macOS" : "Create and start installer") { installGuest() }
                    .disabled(model.isVMInUse || model.vmFolderPath.isEmpty ||
                        (model.guestOS == .macOS ? model.restoreImagePath.isEmpty : model.installationISOPath.isEmpty))
                Button("Start VM") { Task { await model.bootManagedVM() } }
                    .disabled(model.isVMInUse || model.vmFolderPath.isEmpty)
                Button("Stop") { Task { await model.stopVM() } }
                    .disabled(model.provisioning || model.vmOperationInProgress || !model.vm.hasSession)
            }
            if model.guestOS != .macOS {
                Button("Finish installation and eject ISO…") { finishISOInstallation() }
                    .disabled(model.isVMInUse || model.vmFolderPath.isEmpty)
            }
            if model.provisioning && model.guestOS == .macOS {
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
                                Text("\(entry.record.guestOS.title) · \(entry.record.state.rawValue)").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Select") { model.loadHardwareProfile(for: entry.url) }
                                .disabled(model.isVMInUse)
                        }
                    }
                }
            }
            GroupBox("Guest console") {
                if model.guestOS == .windowsARM {
                    ContentUnavailableView("Windows ARM console", systemImage: "desktopcomputer", description:
                        Text("QEMU opens the Windows display in its own window. Control + Option + G captures/releases input. Close that window or use Stop to end the VM."))
                        .frame(minWidth: 550, minHeight: 220)
                } else {
                    VMConsoleView(virtualMachine: model.vm.virtualMachine, hardware: model.hardware)
                        .id(model.vmRevision)
                        .frame(minWidth: 550, minHeight: 300)
                }
            }
            Text("Use a new destination folder for installation, a compatible Apple IPSW or ARM64 ISO, and sufficient disk space. After an ISO installation, shut down the guest, click Stop, then Finish installation and eject ISO before starting from disk.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var installationMediaControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            if model.guestOS == .macOS {
                mediaPicker("Apple macOS restore image (.ipsw)", extension: "ipsw", selection: $model.restoreImagePath)
            } else {
                mediaPicker("ARM64 / AArch64 installer ISO", extension: "iso", selection: $model.installationISOPath)
                Text("Use an ARM64 / AArch64 image; x86 installers cannot boot these VMs.").font(.caption).foregroundStyle(.secondary)
                if model.guestOS == .windowsARM {
                    mediaPicker("Optional ARM64 VirtIO driver ISO", extension: "iso", selection: $model.windowsDriverISOPath)
                    Text("Windows uses QEMU 9.2 or newer, persistent UEFI and TPM 2.0. Install ARM64 VirtIO network drivers from the driver ISO during setup. NAT or disconnected networking is supported.")
                        .font(.caption).foregroundStyle(.secondary)
                    DisclosureGroup("Windows backend paths (automatically detected for Homebrew)") {
                        TextField("qemu-system-aarch64 executable", text: $model.qemuExecutablePath)
                        TextField("swtpm executable", text: $model.swtpmExecutablePath)
                        TextField("AArch64 UEFI code firmware", text: $model.windowsFirmwareCodePath)
                        TextField("UEFI variable-store template", text: $model.windowsFirmwareVariablesPath)
                    }
                }
            }
        }
    }

    private func mediaPicker(_ title: String, extension suffix: String, selection: Binding<String>) -> some View {
        HStack {
            TextField(title, text: selection)
            Button("Choose…") {
                let panel = NSOpenPanel()
                panel.allowedContentTypes = [.init(filenameExtension: suffix)!]
                panel.canChooseDirectories = false
                if panel.runModal() == .OK { selection.wrappedValue = panel.url?.path ?? "" }
            }
        }
    }

    private var hardwareConfiguration: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Instance hardware").font(.title2.bold())
                        Text("Tune this Mac’s virtual hardware. Changes are saved with the selected VM.")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Menu("Presets") {
                        Button("Balanced · 4 cores / 8 GB") { applyHardwarePreset(cpu: 4, memory: 8) }
                        Button("Performance · 8 cores / 16 GB") { applyHardwarePreset(cpu: 8, memory: 16) }
                        Button("Lightweight · 2 cores / 4 GB") { applyHardwarePreset(cpu: 2, memory: 4) }
                    }
                }
                HStack {
                    TextField("Selected VM folder", text: $model.vmFolderPath)
                        .textFieldStyle(.roundedBorder)
                    Button("Load profile") { model.loadConnectivity() }
                        .disabled(model.vmFolderPath.isEmpty)
                }
                HStack(spacing: 12) {
                    metricCard("PROCESSING", value: "\(model.hardware.cpuCount) cores", icon: "cpu.fill", tint: .blue)
                    metricCard("MEMORY", value: "\(model.hardware.memoryGiB) GB", icon: "memorychip.fill", tint: .purple)
                    metricCard("DISPLAY", value: model.hardware.display.title, icon: "display", tint: .orange)
                }
                GroupBox {
                    VStack(alignment: .leading, spacing: 16) {
                        sectionHeading("Identity", subtitle: "A friendly name for this VM instance")
                        TextField("For example, macOS Development", text: $model.hardware.displayName)
                            .textFieldStyle(.roundedBorder)
                    }.padding(4)
                }
                GroupBox {
                    VStack(alignment: .leading, spacing: 16) {
                        sectionHeading("Compute", subtitle: "Choose how much of your Mac to share with the guest")
                        HStack(spacing: 24) {
                            VStack(alignment: .leading, spacing: 9) {
                                Label("Virtual CPU", systemImage: "cpu")
                                Stepper("\(model.hardware.cpuCount) cores", value: $model.hardware.cpuCount, in: 2...max(2, ProcessInfo.processInfo.processorCount), step: 1)
                                Text("Host has \(ProcessInfo.processInfo.processorCount) logical cores").font(.caption).foregroundStyle(.secondary)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                            VStack(alignment: .leading, spacing: 9) {
                                Label("Memory", systemImage: "memorychip")
                                Stepper("\(model.hardware.memoryGiB) GiB", value: $model.hardware.memoryGiB, in: 4...model.safeMaximumMemoryGiB, step: 2)
                                Text("Leave room for macOS and other apps").font(.caption).foregroundStyle(.secondary)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }.padding(4)
                }
                GroupBox {
                    VStack(alignment: .leading, spacing: 14) {
                        sectionHeading("Display", subtitle: "Set the guest’s starting resolution")
                        Label("Apple virtual Mac display · host accelerated where supported", systemImage: "sparkles")
                            .font(.caption).foregroundStyle(.secondary)
                        Picker("Resolution", selection: $model.hardware.display) {
                            ForEach(VMDisplayPreset.allCases) { preset in Text(preset.title).tag(preset) }
                        }.pickerStyle(.segmented)
                        Toggle("Resize guest display with the VM window", isOn: $model.hardware.automaticallyResizeDisplay)
                    }.padding(4)
                }
                GroupBox {
                    VStack(alignment: .leading, spacing: 13) {
                        sectionHeading("Sound", subtitle: "Virtual audio devices presented to macOS")
                        Toggle("Audio output", isOn: $model.hardware.audioOutputEnabled)
                        Toggle("Microphone input", isOn: $model.hardware.microphoneEnabled)
                            .disabled(!model.hardware.audioOutputEnabled)
                        if model.hardware.microphoneEnabled {
                            Label("The guest may request microphone access from macOS.", systemImage: "mic.badge.waveform")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }.padding(4)
                }
                GroupBox {
                    VStack(alignment: .leading, spacing: 13) {
                        sectionHeading("Device passthrough", subtitle: "Host hardware access follows Apple’s virtualization APIs")
                        Label("Apple Neural Engine passthrough is not exposed by Virtualization.framework. Guests cannot claim the host ANE directly.", systemImage: "cpu")
                            .font(.callout).foregroundStyle(.secondary)
                        Label("Physical GPU passthrough is not available for macOS guests. Apple’s Mac graphics device is managed by the host virtualization framework.", systemImage: "display")
                            .font(.callout).foregroundStyle(.secondary)
                        Label("USB accessory passthrough is available only on macOS 27+ through Apple’s AccessoryAccess flow; this app’s deployment target is macOS 15.", systemImage: "cable.connector")
                            .font(.callout).foregroundStyle(.secondary)
                    }.padding(4)
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
                        Text("The release hotkey always stays on the host. Input also releases when the app or VM window loses focus.")
                            .font(.caption).foregroundStyle(.secondary)
                    }.padding(4)
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
                            ForEach($model.hardware.additionalDisks) { $disk in
                                HStack(spacing: 12) {
                                    Image(systemName: "externaldrive.fill").foregroundStyle(.blue)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(URL(fileURLWithPath: disk.path).lastPathComponent).font(.subheadline.weight(.medium))
                                        Text(disk.path).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                                    }
                                    Spacer()
                                    Toggle("Read only", isOn: $disk.readOnly).toggleStyle(.switch)
                                    Button { model.detachDiskImage(disk) } label: {
                                        Image(systemName: "minus.circle")
                                    }.buttonStyle(.borderless)
                                        .help("Detach image without deleting the file")
                                }.padding(10).background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 10))
                            }
                        }
                        Text("Disk images only. Raw device paths and files inside the VM bundle are rejected.")
                            .font(.caption).foregroundStyle(.secondary)
                    }.padding(4)
                }
                HStack {
                    Image(systemName: model.hardwareLoaded ? "checkmark.circle.fill" : "info.circle.fill")
                        .foregroundStyle(model.hardwareLoaded ? .green : .secondary)
                    Text(model.hardwareStatus).font(.callout).foregroundStyle(.secondary)
                    Spacer()
                    Button("Save hardware") { model.saveHardware() }
                        .buttonStyle(.borderedProminent)
                        .disabled(!model.hardwareLoaded || model.vm.virtualMachine != nil || model.provisioning)
                }.padding(.vertical, 4)
                Text("Hardware changes apply on the next VM start. Provisioning uses the current hardware profile; after installation, each instance has its own saved profile.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(.bottom, 12)
            .disabled(model.isVMInUse)
        }
    }

    private func applyHardwarePreset(cpu: Int, memory: Int) {
        model.hardware.cpuCount = min(cpu, max(2, ProcessInfo.processInfo.processorCount))
        model.hardware.memoryGiB = min(memory, max(4, min(64, Int(ProcessInfo.processInfo.physicalMemory / 1_073_741_824) - 4)))
    }

    private func metricCard(_ title: String, value: String, icon: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Image(systemName: icon).font(.title3).foregroundStyle(tint)
            Text(title).font(.system(size: 9, weight: .bold, design: .rounded)).tracking(1.1).foregroundStyle(.secondary)
            Text(value).font(.headline).lineLimit(1).minimumScaleFactor(0.8)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(14)
            .background(tint.opacity(0.075), in: RoundedRectangle(cornerRadius: 14))
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

    private func installGuest() {
        if let path = model.hardware.bootDiskPath {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "Install \(model.guestOS.title) into the selected disk image?"
            alert.informativeText = "Installation can erase all existing data in this image:\n\n\(path)"
            alert.addButton(withTitle: "Cancel")
            alert.addButton(withTitle: "Install \(model.guestOS.title)")
            guard alert.runModal() == .alertSecondButtonReturn else { return }
        }
        Task { await model.provisionVM() }
    }

    private func finishISOInstallation() {
        let alert = NSAlert()
        alert.messageText = "Finish this ISO installation?"
        alert.informativeText = "Complete the guest installer and shut down the guest first. This marks the VM ready and removes the installation ISO from subsequent boots."
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Finish and eject ISO")
        if alert.runModal() == .alertSecondButtonReturn { model.finishARMInstallation() }
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
