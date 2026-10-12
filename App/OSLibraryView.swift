import SwiftUI
import AppKit

struct OSLibraryView: View {
    @EnvironmentObject private var model: AppModel
    @State private var localItems: [OSLibraryItem] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("OS Library").font(.system(.title2, design: .rounded).weight(.bold))
                        Text("Local installers, restore images, and active downloads.").font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { refresh() } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                        .buttonStyle(.bordered)
                }

                WorkspaceCard(title: "Downloads", subtitle: "Monitor downloads started by MacOnMac. Files are staged and moved into place only after completion.") {
                    if model.osDownloads.isEmpty {
                        Label("No downloads yet", systemImage: "arrow.down.circle").foregroundStyle(.secondary)
                    } else {
                        ForEach(model.osDownloads) { download in
                            VStack(alignment: .leading, spacing: 7) {
                                HStack {
                                    Label(download.title, systemImage: download.state == .completed ? "checkmark.circle.fill" : "arrow.down.circle")
                                        .font(.callout.weight(.semibold))
                                    Spacer()
                                    Text(download.state.title).font(.caption).foregroundStyle(.secondary)
                                }
                                if download.state == .downloading { ProgressView(value: download.progress) }
                                Text(download.detail).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                            }
                            .padding(.vertical, 5)
                        }
                    }
                }

                WorkspaceCard(title: "Available media", subtitle: "Installers and restore images already present on this Mac.") {
                    if localItems.isEmpty {
                        ContentUnavailableView("No local OS media found", systemImage: "externaldrive.badge.questionmark",
                            description: Text("Download an Apple restore image or use Terminal to download an official installer."))
                            .frame(maxWidth: .infinity, minHeight: 120)
                    } else {
                        ForEach(localItems) { item in
                            HStack(spacing: 12) {
                                Image(systemName: item.kind == .installer ? "shippingbox" : "doc.zipper")
                                    .foregroundStyle(Color.accentColor)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(item.name).font(.callout.weight(.semibold))
                                    Text(item.path).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                                }
                                Spacer()
                                Button("Reveal") { NSWorkspace.shared.selectFile(item.path, inFileViewerRootedAtPath: "") }
                            }
                        }
                    }
                }

                WorkspaceCard(title: "Official sources", subtitle: "MacOnMac does not mirror operating-system media.") {
                    HStack(spacing: 10) {
                        Button("Apple macOS help") { NSWorkspace.shared.open(OSMediaSource.appleMacOSDownloadPage) }
                        Button("Ubuntu ARM64") { NSWorkspace.shared.open(OSMediaSource.ubuntuARM64Page) }
                        Button("Windows ARM64") { NSWorkspace.shared.open(OSMediaSource.windowsARM64Page) }
                    }
                }
            }
            .padding(.bottom, 18)
        }
        .onAppear { refresh() }
    }

    private func refresh() {
        var items: [OSLibraryItem] = []
        if !model.restoreImagePath.isEmpty, FileManager.default.fileExists(atPath: model.restoreImagePath) {
            items.append(OSLibraryItem(name: URL(fileURLWithPath: model.restoreImagePath).lastPathComponent,
                                       path: model.restoreImagePath, kind: .restoreImage))
        }
        for path in [model.installationISOPath, model.windowsDriverISOPath] where !path.isEmpty && FileManager.default.fileExists(atPath: path) {
            items.append(OSLibraryItem(name: URL(fileURLWithPath: path).lastPathComponent, path: path, kind: .installer))
        }
        if let applications = try? FileManager.default.contentsOfDirectory(at: URL(fileURLWithPath: "/Applications"),
                                                                              includingPropertiesForKeys: [.isDirectoryKey],
                                                                              options: [.skipsHiddenFiles]) {
            items += applications.filter { $0.lastPathComponent.hasPrefix("Install macOS ") && $0.pathExtension == "app" }
                .map { OSLibraryItem(name: $0.lastPathComponent, path: $0.path, kind: .installer) }
        }
        localItems = items.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

struct OSLibraryItem: Identifiable {
    enum Kind { case installer, restoreImage }
    let id = UUID()
    let name: String
    let path: String
    let kind: Kind
}
