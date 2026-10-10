import SwiftUI
import AppKit

@main
struct VolumeBootApp: App {
    @StateObject private var model = AppModel()
    @NSApplicationDelegateAdaptor(VolumeBootApplicationDelegate.self) private var appDelegate
    var body: some Scene {
        WindowGroup("VolumeBoot") {
            DashboardView().environmentObject(model)
                .frame(minWidth: 900, minHeight: 580)
                .onAppear { appDelegate.model = model }
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
        guard model.vm.hasSession else { return .terminateNow }
        if !terminationRequested {
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
