import SwiftUI
import AppKit

struct WorkspaceCard<Content: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline.weight(.semibold))
                if let subtitle { Text(subtitle).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
            }
            content
        }
        .padding(20).frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.primary.opacity(0.075), lineWidth: 1))
        .shadow(color: .black.opacity(0.035), radius: 14, y: 5)
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
        HStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 38, height: 38)
                .background(Color.accentColor.opacity(0.11), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text(title.uppercased()).font(.caption2.weight(.bold)).tracking(0.6).foregroundStyle(.secondary)
                Text(value).font(.title3.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.8)
            }
            Spacer(minLength: 0)
        }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.primary.opacity(0.07), lineWidth: 1))
            .accessibilityElement(children: .combine)
    }
}

struct GuestChoiceCard: View {
    let guest: VMGuestOS
    let selected: Bool
    let action: () -> Void

    private var symbol: String {
        switch guest {
        case .macOS: "apple.logo"
        case .linuxARM: "terminal.fill"
        case .windowsARM: "rectangle.on.rectangle"
        }
    }

    private var detail: String {
        switch guest {
        case .macOS: "Apple Virtualization"
        case .linuxARM: "ARM64 · EFI"
        case .windowsARM: "QEMU · ARM64"
        }
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 13) {
                HStack {
                    Image(systemName: symbol).font(.system(size: 21, weight: .medium))
                        .foregroundStyle(selected ? Color.white : Color.accentColor)
                        .frame(width: 42, height: 42)
                        .background(selected ? Color.white.opacity(0.18) : Color.accentColor.opacity(0.10),
                                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    Spacer()
                    if selected { Image(systemName: "checkmark.circle.fill").font(.title3).foregroundStyle(.white) }
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(guest.title).font(.headline.weight(.semibold))
                    Text(detail).font(.caption).foregroundStyle(selected ? .white.opacity(0.78) : .secondary)
                }
            }
            .padding(14).frame(maxWidth: .infinity, minHeight: 112, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(LinearGradient(
                        colors: selected
                            ? [Color.accentColor, Color(red: 0.25, green: 0.39, blue: 0.88)]
                            : [Color(nsColor: .controlBackgroundColor), Color(nsColor: .controlBackgroundColor)],
                        startPoint: .topLeading, endPoint: .bottomTrailing))
            }
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(selected ? Color.accentColor : Color.primary.opacity(0.08), lineWidth: selected ? 1.5 : 1))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        .accessibilityLabel("\(guest.title), \(detail)\(selected ? ", selected" : "")")
    }
}

struct ResourceStepper<Controls: View>: View {
    let title: String
    let symbol: String
    let value: String
    @ViewBuilder let controls: Controls

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).font(.system(size: 16, weight: .semibold)).foregroundStyle(Color.accentColor)
                .frame(width: 34, height: 34).background(Color.accentColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Text(value).font(.callout.weight(.semibold)).monospacedDigit()
            }
            Spacer(minLength: 0)
            controls
        }
        .padding(11).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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
