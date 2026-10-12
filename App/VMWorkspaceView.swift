import SwiftUI
import AppKit
import UniformTypeIdentifiers

enum VMWorkspaceSection: String, CaseIterable, Identifiable {
    case overview = "Overview", console = "Console", hardware = "Hardware", disks = "Disks", network = "Network"
    var id: String { rawValue }
}

struct VMWorkspaceView<Hardware: View, Network: View>: View {
    @EnvironmentObject private var model: AppModel
    let hardware: Hardware
    let network: Network
    @State private var section: VMWorkspaceSection = .overview
    @State private var backendExpanded = false
    @State private var mediaExpanded = false

    init(hardware: Hardware, network: Network, initialSection: VMWorkspaceSection = .overview) {
        self.hardware = hardware; self.network = network
        _section = State(initialValue: initialSection)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header
            HStack(spacing: 12) {
                Picker("Workspace section", selection: $section) {
                    ForEach(VMWorkspaceSection.allCases) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented).labelsHidden().frame(maxWidth: 480)
                Spacer(minLength: 0)
                if model.currentManifest != nil && model.hasUnsavedChanges { WorkspaceStatus(text: "Unsaved changes", symbol: "pencil.circle", tint: .orange) }
            }
            if let failure = model.vmFailure {
                WorkspaceNotice(text: failure, symbol: "exclamationmark.triangle", tint: .red)
            }
            Group {
                switch section {
                case .overview: overview
                case .console: console
                case .hardware: hardware
                case .disks: VMDiskImagesView()
                case .network: network
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .animation(.easeInOut(duration: 0.16), value: section)
        .onChange(of: model.vmRevision) { _, _ in if model.vm.hasSession { section = .console } }
        .onChange(of: model.vmFolderPath) { _, _ in if !model.vm.hasSession { section = .overview } }
        .alert("Approve Windows backend executable?", isPresented: Binding(
            get: { model.backendApprovalRequest != nil },
            set: { if !$0 { model.cancelBackendExecutableApproval() } }
        )) {
            Button("Trust this exact file") { model.approveBackendExecutable(persistently: true) }
            Button("Allow once") { model.approveBackendExecutable(persistently: false) }
            Button("Cancel", role: .cancel) { model.cancelBackendExecutableApproval() }
        } message: {
            if let identity = model.backendApprovalRequest {
                Text("This VM workspace requests the \(identity.kind.rawValue) executable at:\n\n\(identity.path)\n\nSHA-256: \(identity.sha256)\n\nMacOnMac will check the backend version before launch. Approval applies to these exact file contents. A changed executable requires approval again.")
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            Image(systemName: model.guestOS == .macOS ? "desktopcomputer" : "server.rack")
                .font(.system(size: 24, weight: .medium)).foregroundStyle(.blue)
                .frame(width: 54, height: 54).background(.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 5) {
                Text(model.currentManifest == nil ? "Virtual machines" :
                    model.hardware.displayName.isEmpty ? URL(fileURLWithPath: model.vmFolderPath).lastPathComponent : model.hardware.displayName)
                    .font(.title2.weight(.bold)).lineLimit(1)
                Text(model.currentManifest == nil ? "Create a workspace. Run it on your Mac." : "\(model.guestOS.title) · ARM64")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            stateBadge
            if model.vm.hasSession {
                Button { model.requestShutdown() } label: { Label("Shut down", systemImage: "power") }
                    .disabled(model.shutdownRequested || model.vmOperationInProgress || model.provisioning)
                Menu {
                    Button("Force stop…", role: .destructive) { WorkspaceActions.forceStop(model) }
                } label: { Image(systemName: "ellipsis") }
                    .menuStyle(.borderlessButton).fixedSize().help("More VM actions")
                    .disabled(model.vmOperationInProgress || model.provisioning)
            } else if model.currentManifest != nil {
                Button { Task { await model.bootManagedVM() } } label: { Label("Start", systemImage: "play.fill") }
                    .buttonStyle(.borderedProminent).disabled(!model.canStartVM)
                    .help(model.hasUnsavedChanges ? "Save or reload your changes before starting" : "Start the selected virtual machine")
            }
        }
    }

    @ViewBuilder private var stateBadge: some View {
        if model.provisioning { WorkspaceStatus(text: "Installing", symbol: "arrow.down.circle", tint: .blue) }
        else if model.vmOperationInProgress { WorkspaceStatus(text: "Working", symbol: "hourglass", tint: .blue) }
        else if model.shutdownRequested { WorkspaceStatus(text: "Shutting down", symbol: "power", tint: .orange) }
        else if model.vm.hasSession { WorkspaceStatus(text: "Running", symbol: "play.circle.fill", tint: .green) }
        else if let record = model.currentManifest {
            switch record.state {
            case .installed: WorkspaceStatus(text: "Stopped", symbol: "stop.circle", tint: .secondary)
            case .installing: WorkspaceStatus(text: "Setup in progress", symbol: "wrench", tint: .orange)
            case .failed: WorkspaceStatus(text: "Setup failed", symbol: "exclamationmark.triangle", tint: .red)
            case .provisioning: WorkspaceStatus(text: "Setup interrupted", symbol: "exclamationmark.circle", tint: .orange)
            }
        } else { WorkspaceStatus(text: "New workspace", symbol: "plus.circle", tint: .blue) }
    }

    private var overview: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let record = model.currentManifest { existingOverview(record) }
                else { newVMSetup }
                if !model.knownVMs.isEmpty { library }
            }.padding(.bottom, 16)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if model.currentManifest == nil { setupFooter }
        }
    }

    private var setupFooter: some View {
        HStack(spacing: 12) {
            if model.provisioning {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: "bolt.fill").foregroundStyle(Color.accentColor)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(footerTitle)
                    .font(.callout.weight(.semibold)).lineLimit(1).textSelection(.enabled)
                if model.provisioning && model.guestOS == .macOS {
                    ProgressView(value: model.installProgress).frame(maxWidth: 220)
                } else if !model.provisioning {
                    Text("Your configuration is saved locally on this Mac.").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 12)
            Button { installGuest() } label: {
                Label(model.guestOS == .macOS ? "Install macOS" : "Create VM", systemImage: "sparkles")
            }.buttonStyle(.borderedProminent).controlSize(.large).disabled(!model.canCreateVM)
        }
        .padding(.horizontal, 18).padding(.vertical, 12)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(alignment: .top) { Rectangle().fill(.primary.opacity(0.08)).frame(height: 1) }
    }

    private var footerTitle: String {
        if model.provisioning { return "Working on your VM" }
        if model.canCreateVM { return "Ready to create" }
        return "Choose an installer and destination"
    }

    private func existingOverview(_ record: ManagedVMManifest) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 12) {
                WorkspaceMetric(title: "Processor", value: "\(model.hardware.cpuCount) cores", symbol: "cpu")
                WorkspaceMetric(title: "Memory", value: "\(model.hardware.memoryGiB) GiB", symbol: "memorychip")
                WorkspaceMetric(title: "Storage", value: "\(model.hardware.additionalDisks.count + 1) disk images", symbol: "internaldrive")
                WorkspaceMetric(title: "Network", value: model.connectivity.networkMode == .nat ? "NAT" : model.connectivity.networkMode.rawValue.capitalized, symbol: "network")
            }
            WorkspaceCard(title: "Workspace", subtitle: "The VM folder keeps its identity, settings, and installation state.") {
                Text(model.vmFolderPath).font(.callout.monospaced()).lineLimit(1).truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
                HStack {
                    Button("Reveal in Finder") { NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: model.vmFolderPath) }
                    Button("Validate configuration") { model.validateVMConfiguration() }
                    Spacer()
                    Button("Manage disks") { section = .disks }
                }
                if let lastFailure = record.lastFailure { WorkspaceNotice(text: lastFailure, symbol: "exclamationmark.triangle", tint: .orange) }
                if let validation = model.validationSummary {
                    WorkspaceNotice(text: validation, symbol: model.validationIssues.isEmpty ? "checkmark.circle" : "exclamationmark.triangle",
                                    tint: model.validationIssues.isEmpty ? .green : .orange)
                }
                if model.hasUnsavedChanges {
                    WorkspaceNotice(text: "Save your changes in Hardware, Network, or Media before starting. Reload restores the saved profile.", symbol: "pencil.circle", tint: .orange)
                    Button("Reload saved profile…") {
                        if WorkspaceActions.allowDiscard(model) { model.loadHardwareProfile(for: URL(fileURLWithPath: model.vmFolderPath)) }
                    }.disabled(!model.canSelectVM)
                }
            }
            if record.state == .installing {
                WorkspaceCard(title: "Complete installation", subtitle: "Finish setup inside the guest and shut it down. Then eject the installer to boot from disk.") {
                    Button("Finish installation and eject ISO…") { finishInstallation() }
                        .disabled(!model.canFinishInstallation)
                }
            }
            if record.guestOS != .macOS {
                WorkspaceCard(title: "Installation media") {
                    DisclosureGroup("Installer, driver media, and backend paths", isExpanded: $mediaExpanded) {
                        VStack(alignment: .leading, spacing: 16) {
                            mediaControls
                            Button("Save media settings") { model.saveARMGuestMedia() }
                                .disabled(model.isVMInUse || !model.hasUnsavedMedia)
                        }.padding(.top, 12)
                    }
                }
            }
            WorkspaceNotice(text: model.vmStatus)
        }
    }

    private var newVMSetup: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 7) {
                Text("Your next machine starts here")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .tracking(-0.7)
                Text("Choose a guest, point to its installer, and MacOnMac will take care of the workspace.")
                    .font(.callout).foregroundStyle(.secondary)
            }.padding(.horizontal, 3).padding(.top, 4)

            WorkspaceCard(title: "01  ·  Choose a guest", subtitle: "Evaluation preview: guest installation and host-version qualification are still pending. See the release support matrix.") {
                HStack(spacing: 10) {
                    ForEach(VMGuestOS.allCases) { guest in
                        GuestChoiceCard(guest: guest, selected: model.guestOS == guest) {
                            model.selectNewGuest(guest)
                        }
                    }
                }
            }.disabled(model.isVMInUse)

            WorkspaceCard(title: "02  ·  Installation and location", subtitle: "Your VM is stored locally in a dedicated folder.") {
                WorkspacePathField(title: "Workspace destination", placeholder: "Choose a new folder", path: $model.vmFolderPath) { chooseDestination() }
                if !model.vmFolderPath.isEmpty && FileManager.default.fileExists(atPath: model.vmFolderPath) {
                    WorkspaceNotice(text: "This folder already exists. Choose a new destination or open it as an existing VM.", symbol: "exclamationmark.triangle", tint: .orange)
                }
                mediaControls
            }.disabled(model.isVMInUse)

            WorkspaceCard(title: "03  ·  Performance profile", subtitle: "Tune resources now; change them later without rebuilding the VM.") {
                HStack {
                    Label("Quick profile", systemImage: "slider.horizontal.3").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                    Spacer()
                    Menu("Choose profile") {
                        Button("Balanced · 4 CPU / 8 GiB") { applyQuickProfile(cpu: 4, memory: 8) }
                        Button("High performance · max available") { applyQuickProfile(cpu: model.maximumCPUCount, memory: model.safeMaximumMemoryGiB) }
                        Button("Lightweight · 2 CPU / 4 GiB") { applyQuickProfile(cpu: 2, memory: 4) }
                    }
                }
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) { resourceControls }
                    VStack(spacing: 10) { resourceControls }
                }
                if let path = model.hardware.bootDiskPath {
                    WorkspaceNotice(text: "Install target: \(path). Installation may erase existing data.", symbol: "externaldrive", tint: .orange)
                }
                HStack {
                    Button("Advanced hardware") { section = .hardware }
                    Button("Manage disk images") { section = .disks }
                    Spacer()
                    Label("Optimized for Apple Silicon", systemImage: "bolt.fill")
                        .font(.caption.weight(.medium)).foregroundStyle(.secondary)
                }
            }.disabled(model.isVMInUse)
        }
    }

    private var mediaControls: some View {
        VStack(alignment: .leading, spacing: 14) {
            if model.guestOS == .macOS {
                WorkspacePathField(title: "macOS restore image", placeholder: "Apple Silicon .ipsw file", path: $model.restoreImagePath) { chooseMedia("ipsw", binding: $model.restoreImagePath) }
            } else {
                WorkspacePathField(title: "Installation media", placeholder: "ARM64 / AArch64 .iso file", path: $model.installationISOPath) { chooseMedia("iso", binding: $model.installationISOPath) }
                Text("Use an ARM64 image with EFI support. x86 installers cannot boot this workspace.").font(.caption).foregroundStyle(.secondary)
                if model.guestOS == .windowsARM {
                    WorkspacePathField(title: "Network driver media (optional)", placeholder: "ISO containing ARM64 VirtIO drivers", path: $model.windowsDriverISOPath) { chooseMedia("iso", binding: $model.windowsDriverISOPath) }
                    Text("Windows requires QEMU 9.2+ and swtpm. Install the ARM64 VirtIO network driver to use NAT networking.").font(.caption).foregroundStyle(.secondary)
                    DisclosureGroup("Windows backend", isExpanded: $backendExpanded) {
                        VStack(alignment: .leading, spacing: 12) {
                            WorkspacePathField(title: "QEMU executable", placeholder: "Detected automatically for Homebrew", path: $model.qemuExecutablePath) { chooseMedia(nil, binding: $model.qemuExecutablePath) }
                            WorkspacePathField(title: "swtpm executable", placeholder: "Detected automatically for Homebrew", path: $model.swtpmExecutablePath) { chooseMedia(nil, binding: $model.swtpmExecutablePath) }
                            if model.currentManifest == nil {
                                WorkspacePathField(title: "UEFI code template", placeholder: "Optional firmware override", path: $model.windowsFirmwareCodePath) { chooseMedia("fd", binding: $model.windowsFirmwareCodePath) }
                                WorkspacePathField(title: "UEFI variables template", placeholder: "Optional firmware override", path: $model.windowsFirmwareVariablesPath) { chooseMedia("fd", binding: $model.windowsFirmwareVariablesPath) }
                            }
                        }.padding(.top, 12)
                    }
                }
            }
        }.disabled(model.isVMInUse)
    }

    private var console: some View {
        VStack(spacing: 16) {
            if model.vm.hasSession && model.guestOS != .windowsARM {
                VMConsoleView(virtualMachine: model.vm.virtualMachine, hardware: model.hardware)
                    .id(model.vmRevision).frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            } else {
                ContentUnavailableView {
                    Label(model.vm.usesExternalConsole ? "Windows console is open" : "Your console is ready", systemImage: "display")
                } description: {
                    Text(model.vm.usesExternalConsole ? "Windows runs in a separate display window. Control + Option + G captures or releases input." :
                         "Start a virtual machine to view its display and use mouse capture controls.")
                } actions: {
                    if model.vm.usesExternalConsole { Button("Show Windows console") { model.showExternalConsole() } }
                    else if model.canStartVM { Button("Start VM") { Task { await model.bootManagedVM() } }.buttonStyle(.borderedProminent) }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            WorkspaceNotice(text: model.vmStatus)
        }
    }

    private var library: some View {
        WorkspaceCard(title: "VM library", subtitle: "Recent workspaces and VMs in the selected folder’s parent directory.") {
            ForEach(model.knownVMs, id: \.url.path) { entry in
                HStack(spacing: 12) {
                    Image(systemName: guestSymbol(entry.record.guestOS)).foregroundStyle(Color.accentColor)
                        .frame(width: 36, height: 36)
                        .background(Color.accentColor.opacity(0.09), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(entry.url.lastPathComponent).font(.callout.weight(.semibold)).help(entry.url.path)
                        Text("\(entry.record.guestOS.title) · \(entry.record.state == .installed ? "Installed" : entry.record.state.rawValue.capitalized)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if entry.url.path == model.vmFolderPath {
                        WorkspaceStatus(text: "Selected", symbol: "checkmark.circle.fill", tint: .green)
                    } else {
                        Button("Open") {
                            if WorkspaceActions.allowDiscard(model) { model.loadHardwareProfile(for: entry.url) }
                        }.buttonStyle(.bordered).disabled(!model.canSelectVM)
                    }
                }.padding(.vertical, 3)
            }
        }
    }

    @ViewBuilder private var resourceControls: some View {
        ResourceStepper(title: "CPU", symbol: "cpu", value: "\(model.hardware.cpuCount) cores") {
            Stepper("CPU cores", value: $model.hardware.cpuCount, in: 2...model.maximumCPUCount)
                .labelsHidden().accessibilityLabel("CPU cores")
        }
        ResourceStepper(title: "Memory", symbol: "memorychip", value: "\(model.hardware.memoryGiB) GiB") {
            Stepper("Memory", value: $model.hardware.memoryGiB, in: 4...model.safeMaximumMemoryGiB, step: 2)
                .labelsHidden().accessibilityLabel("Memory")
        }
        ResourceStepper(title: "Boot disk", symbol: "internaldrive", value: "\(model.diskSizeGiB) GiB") {
            Stepper("Boot disk size", value: $model.diskSizeGiB, in: 64...2048, step: 16)
                .labelsHidden().accessibilityLabel("Boot disk size")
                .disabled(model.hardware.bootDiskPath != nil)
        }
    }

    private func applyQuickProfile(cpu: Int, memory: Int) {
        model.hardware.cpuCount = min(max(2, cpu), model.maximumCPUCount)
        model.hardware.memoryGiB = min(max(4, memory), model.safeMaximumMemoryGiB)
    }

    private func guestSymbol(_ guest: VMGuestOS) -> String {
        switch guest {
        case .macOS: "apple.logo"
        case .linuxARM: "terminal.fill"
        case .windowsARM: "rectangle.on.rectangle"
        }
    }

    private func chooseDestination() {
        let panel = NSSavePanel()
        panel.title = "Choose a workspace destination"; panel.prompt = "Use destination"
        panel.nameFieldStringValue = "\(model.guestOS.title) VM"
        panel.message = "Choose a new folder name. Existing folders cannot be used for installation."
        if panel.runModal() == .OK, let url = panel.url { model.vmFolderPath = url.path }
    }

    private func chooseMedia(_ suffix: String?, binding: Binding<String>) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        if let suffix, let type = UTType(filenameExtension: suffix) { panel.allowedContentTypes = [type] }
        if panel.runModal() == .OK, let url = panel.url { binding.wrappedValue = url.path }
    }

    private func installGuest() {
        if let path = model.hardware.bootDiskPath {
            let alert = NSAlert(); alert.alertStyle = .warning
            alert.messageText = "Install \(model.guestOS.title) into this disk image?"
            alert.informativeText = "Installation may erase all existing data in:\n\n\(path)"
            alert.addButton(withTitle: "Cancel"); alert.addButton(withTitle: "Install")
            guard alert.runModal() == .alertSecondButtonReturn else { return }
        }
        Task { await model.provisionVM() }
    }

    private func finishInstallation() {
        let alert = NSAlert()
        alert.messageText = "Finish installation and eject the installer?"
        alert.informativeText = "Confirm that guest setup is complete and the guest is shut down. Its next start will boot from disk."
        alert.addButton(withTitle: "Cancel"); alert.addButton(withTitle: "Finish and eject")
        if alert.runModal() == .alertSecondButtonReturn { model.finishARMInstallation() }
    }
}
