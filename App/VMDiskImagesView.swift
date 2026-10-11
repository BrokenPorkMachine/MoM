import SwiftUI
import AppKit

struct VMDiskImagesView: View {
    @EnvironmentObject private var model: AppModel
    @State private var createSizeGiB = 80
    @State private var createAsBootDisk = false
    @State private var createPresented = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Disk images").font(.title2.weight(.bold))
                        Text("Storage selections are saved automatically for an existing VM.").font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { createPresented = true } label: { Label("Create image", systemImage: "plus") }
                        .disabled(model.isVMInUse || model.vmFolderPath.isEmpty)
                }
                if model.vmFolderPath.isEmpty {
                    WorkspaceNotice(text: "Choose a workspace destination in Overview before creating or attaching images.", symbol: "folder")
                }
                WorkspaceCard(title: "Boot disk", subtitle: "The primary disk used for installation and startup.") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Button("Load boot image…") { chooseImage(asBootDisk: true) }
                            Button("Use bundle disk.img") { model.useBundleBootDisk() }
                        }.disabled(model.isVMInUse || model.vmFolderPath.isEmpty)
                        if model.vmFolderPath.hasPrefix("/"), model.currentManifest != nil || model.hardware.bootDiskPath != nil {
                            VMDiskImageRow(url: model.hardware.bootDiskURL(in: URL(fileURLWithPath: model.vmFolderPath)), isBootDisk: true)
                        } else {
                            Label("A new disk.img will be created during installation", systemImage: "internaldrive")
                                .font(.callout).foregroundStyle(.secondary)
                        }
                        Text("Installation writes to the selected boot image. Keep the original VM folder when loading an installed image; macOS needs its matching hardware model, machine identifier, and auxiliary storage.")
                            .font(.caption).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(6)
                }
                WorkspaceCard(title: "Secondary storage", subtitle: "Attach up to eight raw images. Detaching keeps the file on your Mac.") {
                    VStack(alignment: .leading, spacing: 12) {
                        Button("Load secondary image…") { chooseImage(asBootDisk: false) }
                            .disabled(model.isVMInUse || model.vmFolderPath.isEmpty)
                        ForEach(model.hardware.additionalDisks) { disk in
                            VMDiskImageRow(url: URL(fileURLWithPath: disk.path), isBootDisk: false, disk: disk)
                        }
                        if model.hardware.additionalDisks.isEmpty {
                            ContentUnavailableView("No secondary storage", systemImage: "externaldrive", description: Text("Load an existing .img or .raw file, or create a sparse image."))
                                .frame(height: 140)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(6)
                }
                WorkspaceNotice(text: model.diskImageStatus, symbol: "externaldrive")
                Text("Stop the VM before changing images. Growth changes the virtual disk capacity; expand the guest partition and filesystem afterward. Shrinking is unavailable because it can destroy guest data.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(.bottom, 16)
        }
        .sheet(isPresented: $createPresented) {
            VStack(alignment: .leading, spacing: 20) {
                Text("Create a disk image").font(.title2.weight(.bold))
                Text("A sparse raw image grows on the host as the guest writes data.").foregroundStyle(.secondary)
                Toggle("Use as the boot disk", isOn: $createAsBootDisk)
                    .onChange(of: createAsBootDisk) { _, boot in if boot { createSizeGiB = max(64, createSizeGiB) } }
                Stepper("Capacity: \(createSizeGiB) GiB", value: $createSizeGiB, in: (createAsBootDisk ? 64 : 1)...2048)
                WorkspaceNotice(text: "Keep sufficient free space for installation and continued use. Creation never overwrites an existing file.")
                HStack {
                    Button("Cancel") { createPresented = false }.keyboardShortcut(.cancelAction)
                    Spacer()
                    Button("Choose location…") {
                        let panel = NSSavePanel()
                        panel.allowedContentTypes = [.init(filenameExtension: "img")!, .init(filenameExtension: "raw")!]
                        panel.nameFieldStringValue = createAsBootDisk ? "Boot.img" : "Storage.img"
                        if panel.runModal() == .OK, let url = panel.url {
                            model.createDiskImage(at: url, sizeGiB: createSizeGiB, asBootDisk: createAsBootDisk)
                            createPresented = false
                        }
                    }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction).disabled(model.isVMInUse)
                }
            }.padding(28).frame(width: 480)
        }
    }

    private func chooseImage(asBootDisk: Bool) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.init(filenameExtension: "img")!, .init(filenameExtension: "raw")!]
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url { model.selectDiskImage(url, asBootDisk: asBootDisk) }
    }
}

private struct VMDiskImageRow: View {
    @EnvironmentObject private var model: AppModel
    let url: URL
    let isBootDisk: Bool
    var disk: VMAdditionalDisk?
    @State private var info: VMDiskImageInfo?
    @State private var loadError = ""
    @State private var resizePresented = false
    @State private var newSizeGiB = 80

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: isBootDisk ? "internaldrive.fill" : "externaldrive.fill").font(.title2).foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 5) {
                    Text(url.lastPathComponent).font(.headline)
                    Text(url.path).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle).textSelection(.enabled).help(url.path)
                }
                Spacer()
                if let disk { WorkspaceStatus(text: disk.readOnly ? "Read only" : "Writable", symbol: disk.readOnly ? "lock" : "pencil") }
            }
            if let info {
                Text(String(format: "%.1f GiB capacity · %@ used on host", info.sizeGiB,
                    ByteCountFormatter.string(fromByteCount: Int64(info.allocatedBytes), countStyle: .file)))
                    .font(.caption).foregroundStyle(.secondary)
            } else { Label(loadError, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange) }
            HStack {
                Button("Grow…") {
                    newSizeGiB = min(2048, max(isBootDisk ? 64 : 1, Int(ceil(info?.sizeGiB ?? 64)) + 16))
                    resizePresented = true
                }.disabled(info == nil || (info?.sizeBytes ?? 0) >= VMDiskImageStore.maximumBytes || disk?.readOnly == true)
                if let disk {
                    Toggle("Read only", isOn: Binding(get: { disk.readOnly }, set: { model.setDiskReadOnly(disk, $0) })).toggleStyle(.switch)
                    Button("Detach") { model.detachDiskImage(disk) }
                }
                Spacer()
                Menu("Actions") {
                    Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                    Button("Copy path") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(url.path, forType: .string) }
                    Divider()
                    Button("Delete image file…", role: .destructive) { confirmDelete() }.disabled(info == nil)
                }
            }.disabled(model.isVMInUse)
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 9))
        .task(id: "\(url.path):\(model.diskRevision)") {
            do { info = try VMDiskImageStore.inspect(at: url); loadError = "" }
            catch { info = nil; loadError = error.localizedDescription }
        }
        .sheet(isPresented: $resizePresented) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Grow \(url.lastPathComponent)").font(.headline)
                Stepper("New capacity: \(newSizeGiB) GiB", value: $newSizeGiB, in: (isBootDisk ? 64 : 1)...2048)
                Text("Existing data is preserved. Expand the partition and filesystem inside the guest after restarting.")
                HStack {
                    Button("Cancel") { resizePresented = false }.keyboardShortcut(.cancelAction)
                    Button("Grow image") {
                        model.growDiskImage(at: url, toGiB: newSizeGiB)
                        resizePresented = false
                    }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                        .disabled(model.isVMInUse || UInt64(newSizeGiB) * VMDiskImageStore.gibibyte <= (info?.sizeBytes ?? 0))
                }
            }.padding(24).frame(width: 430)
        }
    }

    private func confirmDelete() {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Permanently delete \(url.lastPathComponent)?"
        alert.informativeText = "All data in this image will be lost.\n\n\(url.path)" +
            (isBootDisk ? "\n\nThis VM cannot boot from this image after deletion." : "")
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Delete image")
        if alert.runModal() == .alertSecondButtonReturn { model.deleteDiskImage(at: url) }
    }
}
