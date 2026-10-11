import SwiftUI
import AppKit

@main
struct VolumeBootApp: App {
    @StateObject private var model = AppModel(preferences: UserDefaults.standard)
    @NSApplicationDelegateAdaptor(VolumeBootApplicationDelegate.self) private var appDelegate
    var body: some Scene {
        WindowGroup("MoM: MacOnMac") {
            DashboardView().environmentObject(model)
                .frame(minWidth: 1000, minHeight: 640)
                .onAppear { appDelegate.model = model }
        }
        .defaultSize(width: 1280, height: 860)
        .commands {
            CommandGroup(after: .newItem) {
                Button("New Virtual Machine") {
                    if WorkspaceActions.allowDiscard(model) { model.beginNewVM() }
                }.keyboardShortcut("n", modifiers: [.command, .shift]).disabled(!model.canSelectVM)
                Button("Open Virtual Machine…") { WorkspaceActions.openVM(model) }
                    .keyboardShortcut("o").disabled(!model.canSelectVM)
            }
        }
    }
}

@MainActor
final class VolumeBootApplicationDelegate: NSObject, NSApplicationDelegate {
    weak var model: AppModel?
    private var terminationRequested = false

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let model else { return .terminateNow }
        guard model.canBeginQuit() else { return .terminateCancel }
        guard WorkspaceActions.allowDiscard(model) else { return .terminateCancel }
        guard model.vm.hasSession else { return .terminateNow }
        if !terminationRequested {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "Quit and stop the running VM?"
            alert.informativeText = "Stopping immediately can lose unsaved guest work. Cancel and use Shut down to close the guest safely."
            alert.addButton(withTitle: "Cancel")
            alert.addButton(withTitle: "Stop VM and quit")
            guard alert.runModal() == .alertSecondButtonReturn else { return .terminateCancel }
            terminationRequested = true
            Task { @MainActor in
                await model.stopVM()
                terminationRequested = false
                sender.reply(toApplicationShouldTerminate: !model.vm.hasSession)
            }
        }
        return .terminateLater
    }
}
