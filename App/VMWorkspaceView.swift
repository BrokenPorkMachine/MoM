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
        .onChange(of: model.vmRevision) { _, _ in if model.vm.hasSession { section = .console } }
        .onChange(of: model.vmFolderPath) { _, _ in if !model.vm.hasSession { section = .overview } }
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
                Text(model.vmFolderPath).font(.callout.monospaced()).textSelection(.enabled)
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
        VStack(alignment: .leading, spacing: 20) {
            WorkspaceCard(title: "Create a virtual machine", subtitle: "Choose an operating system and local installation media. Your workspace will be kept in its own folder.") {
                Picker("Operating system", selection: Binding(get: { model.guestOS }, set: { model.selectNewGuest($0) })) {
                    ForEach(VMGuestOS.allCases) { Text($0.title).tag($0) }
                }.pickerStyle(.segmented)
                WorkspacePathField(title: "Workspace destination", placeholder: "Choose a new folder", path: $model.vmFolderPath) { chooseDestination() }
                if !model.vmFolderPath.isEmpty && FileManager.default.fileExists(atPath: model.vmFolderPath) {
                    WorkspaceNotice(text: "This destination already exists. Choose a new folder, or use Open VM to load an existing workspace.", symbol: "exclamationmark.triangle", tint: .orange)
                }
                mediaControls
            }.disabled(model.isVMInUse)
            WorkspaceCard(title: "Resources", subtitle: "Keep memory available for macOS and other applications.") {
                HStack(spacing: 20) {
                    Stepper("\(model.hardware.cpuCount) CPU cores", value: $model.hardware.cpuCount, in: 2...model.maximumCPUCount)
                    Stepper("\(model.hardware.memoryGiB) GiB memory", value: $model.hardware.memoryGiB, in: 4...model.safeMaximumMemoryGiB)
                    Stepper("\(model.diskSizeGiB) GiB boot disk", value: $model.diskSizeGiB, in: 64...2048, step: 16)
                        .disabled(model.hardware.bootDiskPath != nil)
                }
                if let path = model.hardware.bootDiskPath {
                    WorkspaceNotice(text: "Installation target: \(path). Installing may erase existing data.", symbol: "externaldrive", tint: .orange)
                }
                HStack {
                    Button("Advanced hardware") { section = .hardware }
                    Button("Use a disk image") { section = .disks }
                    Spacer()
                    Text("Raw disk · 64 GiB minimum").font(.caption).foregroundStyle(.secondary)
                }
            }.disabled(model.isVMInUse)
            HStack(spacing: 14) {
                if model.provisioning { ProgressView().controlSize(.small) }
                Text(model.vmStatus).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                Spacer()
                Button { installGuest() } label: {
                    Label(model.guestOS == .macOS ? "Install macOS" : "Create and start installer", systemImage: "plus.circle.fill")
                }.buttonStyle(.borderedProminent).controlSize(.large)
                    .disabled(!model.canCreateVM)
            }
            if model.provisioning && model.guestOS == .macOS {
                ProgressView(value: model.installProgress) { Text("Installing macOS") }
            }
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
                    Image(systemName: "desktopcomputer").foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(entry.url.lastPathComponent).font(.callout.weight(.semibold)).help(entry.url.path)
                        Text("\(entry.record.guestOS.title) · \(entry.record.state == .installed ? "Installed" : entry.record.state.rawValue.capitalized)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(entry.url.path == model.vmFolderPath ? "Selected" : "Open") {
                        if WorkspaceActions.allowDiscard(model) { model.loadHardwareProfile(for: entry.url) }
                    }.disabled(!model.canSelectVM || entry.url.path == model.vmFolderPath)
                }.padding(.vertical, 3)
            }
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
