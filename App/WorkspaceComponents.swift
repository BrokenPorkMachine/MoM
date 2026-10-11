import SwiftUI
import AppKit

struct WorkspaceCard<Content: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                if let subtitle { Text(subtitle).font(.callout).foregroundStyle(.secondary) }
            }
            content
        }
        .padding(20).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.primary.opacity(0.08), lineWidth: 1))
    }
}

struct WorkspaceStatus: View {
    let text: String
    var symbol = "circle.fill"
    var tint: Color = .secondary
    var body: some View {
        Label(text, systemImage: symbol).font(.caption.weight(.semibold))
            .foregroundStyle(tint).padding(.horizontal, 10).padding(.vertical, 6)
            .background(tint.opacity(0.10), in: Capsule())
            .accessibilityLabel(text)
    }
}

struct WorkspaceMetric: View {
    let title: String
    let value: String
    let symbol: String
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: symbol).font(.caption.weight(.medium)).foregroundStyle(.secondary)
            Text(value).font(.title3.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.8)
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(.primary.opacity(0.07), lineWidth: 1))
            .accessibilityElement(children: .combine)
    }
}

struct WorkspaceNotice: View {
    let text: String
    var symbol = "info.circle"
    var tint: Color = .secondary
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol).foregroundStyle(tint).padding(.top, 2)
            Text(text).font(.callout).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
        }.padding(14).background(tint.opacity(0.07), in: RoundedRectangle(cornerRadius: 9))
            .accessibilityElement(children: .combine)
    }
}

struct WorkspacePathField: View {
    let title: String
    var placeholder = "Choose a file"
    @Binding var path: String
    var choose: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.callout.weight(.medium))
            HStack(spacing: 8) {
                TextField(placeholder, text: $path).textFieldStyle(.roundedBorder)
                    .accessibilityLabel(title).help(path.isEmpty ? title : path)
                Button("Browse…", action: choose).help("Choose \(title.lowercased())")
            }
        }
    }
}

@MainActor
enum WorkspaceActions {
    static func allowDiscard(_ model: AppModel) -> Bool {
        guard model.hasUnsavedChanges else { return true }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Discard unsaved changes?"
        alert.informativeText = model.currentManifest == nil ? "Your new VM configuration has not been created." : "Hardware, network, or media changes have not been saved."
        alert.addButton(withTitle: "Keep editing")
        alert.addButton(withTitle: "Discard changes")
        return alert.runModal() == .alertSecondButtonReturn
    }

    static func openVM(_ model: AppModel) {
        guard model.canSelectVM, allowDiscard(model) else { return }
        let panel = NSOpenPanel()
        panel.title = "Open virtual machine"
        panel.message = "Choose the VM folder containing manifest.json and its identity files."
        panel.canChooseDirectories = true; panel.canChooseFiles = false
        panel.prompt = "Open VM"
        if panel.runModal() == .OK, let url = panel.url { model.loadHardwareProfile(for: url) }
    }

    static func forceStop(_ model: AppModel) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Force stop this virtual machine?"
        alert.informativeText = "The guest powers off immediately. Unsaved work may be lost. Use Shut down to let the guest close safely."
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Force stop")
        if alert.runModal() == .alertSecondButtonReturn { Task { await model.stopVM() } }
    }
}
