import SwiftUI
import AppKit

struct VMDiskImagesView: View {
    @EnvironmentObject private var model: AppModel
    @State private var createSizeGiB = 80
    @State private var createAsBootDisk = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Disk images").font(.title2.bold())
                Text("Create sparse raw images, choose the boot disk, or attach secondary storage. Disk selections are saved with an existing VM.")
                    .foregroundStyle(.secondary)
                TextField("VM bundle folder", text: $model.vmFolderPath)
                    .disabled(model.isVMInUse)
                GroupBox("Boot disk") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Button("Load boot image…") { chooseImage(asBootDisk: true) }
                            Button("Use bundle disk.img") { model.useBundleBootDisk() }
                        }.disabled(model.isVMInUse || model.vmFolderPath.isEmpty)
                        if model.vmFolderPath.hasPrefix("/") {
                            VMDiskImageRow(url: model.hardware.bootDiskURL(in: URL(fileURLWithPath: model.vmFolderPath)), isBootDisk: true)
                        }
                        Text("Installation writes to the selected boot image. Keep the original VM folder when loading an installed image; macOS needs its matching hardware model, machine identifier, and auxiliary storage.")
                            .font(.caption).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(6)
                }
                GroupBox("Create an image") {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("Use as the boot disk", isOn: $createAsBootDisk)
                            .onChange(of: createAsBootDisk) { _, boot in if boot { createSizeGiB = max(64, createSizeGiB) } }
                        Stepper("Capacity: \(createSizeGiB) GiB", value: $createSizeGiB, in: (createAsBootDisk ? 64 : 1)...2048)
                        Button("Create disk image…") {
                            let panel = NSSavePanel()
                            panel.allowedContentTypes = [.init(filenameExtension: "img")!, .init(filenameExtension: "raw")!]
                            panel.nameFieldStringValue = createAsBootDisk ? "Boot.img" : "Storage.img"
                            if panel.runModal() == .OK, let url = panel.url {
                                model.createDiskImage(at: url, sizeGiB: createSizeGiB, asBootDisk: createAsBootDisk)
                            }
                        }
                        Text("Capacity is allocated as the guest writes data. Keep enough free space on the host for installation and continued use.")
                            .font(.caption).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(6)
                }.disabled(model.isVMInUse || model.vmFolderPath.isEmpty)
                GroupBox("Secondary images") {
                    VStack(alignment: .leading, spacing: 12) {
                        Button("Load secondary image…") { chooseImage(asBootDisk: false) }
                            .disabled(model.isVMInUse || model.vmFolderPath.isEmpty)
                        ForEach(model.hardware.additionalDisks) { disk in
                            VMDiskImageRow(url: URL(fileURLWithPath: disk.path), isBootDisk: false, disk: disk)
                        }
                        if model.hardware.additionalDisks.isEmpty { Text("No secondary images attached").foregroundStyle(.secondary) }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(6)
                }
                Text(model.diskImageStatus).foregroundStyle(.secondary).textSelection(.enabled)
                Text("Stop the VM before changing images. Growth changes the virtual disk capacity; expand the guest partition and filesystem afterward. Shrinking is unavailable because it can destroy guest data.")
                    .font(.caption).foregroundStyle(.secondary)
            }
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
            Label(url.lastPathComponent, systemImage: isBootDisk ? "internaldrive" : "externaldrive").font(.headline)
            Text(url.path).font(.caption).textSelection(.enabled)
            if let info {
                Text(String(format: "%.1f GiB capacity · %@ used on host", info.sizeGiB,
                    ByteCountFormatter.string(fromByteCount: Int64(info.allocatedBytes), countStyle: .file)))
                    .font(.caption).foregroundStyle(.secondary)
            } else { Text(loadError).font(.caption).foregroundStyle(.secondary) }
            HStack {
                Button("Grow…") {
                    newSizeGiB = min(2048, max(isBootDisk ? 64 : 1, Int(ceil(info?.sizeGiB ?? 64)) + 16))
                    resizePresented = true
                }.disabled(info == nil || (info?.sizeBytes ?? 0) >= VMDiskImageStore.maximumBytes || disk?.readOnly == true)
                if let disk {
                    Text(disk.readOnly ? "Read only" : "Writable").font(.caption)
                    Button("Detach") { model.detachDiskImage(disk) }
                }
                Button("Delete file…", role: .destructive) { confirmDelete() }.disabled(info == nil)
            }.disabled(model.isVMInUse)
        }
        .padding(10).frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
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
                    }.disabled(model.isVMInUse || UInt64(newSizeGiB) * VMDiskImageStore.gibibyte <= (info?.sizeBytes ?? 0))
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
