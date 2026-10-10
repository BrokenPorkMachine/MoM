import SwiftUI
import Virtualization

/// Keep the view linked to the live VM; do not attempt to recreate it during redraws.
struct VMConsoleView: NSViewRepresentable {
    let virtualMachine: VZVirtualMachine?
    let hardware: VMHardwareSettings
    func makeNSView(context: Context) -> VZVirtualMachineView {
        let view = VZVirtualMachineView()
        view.capturesSystemKeys = hardware.capturesSystemKeys
        view.automaticallyReconfiguresDisplay = hardware.automaticallyResizeDisplay
        view.virtualMachine = virtualMachine
        view.capturesSystemKeys = hardware.capturesSystemKeys
        view.automaticallyReconfiguresDisplay = hardware.automaticallyResizeDisplay
        return view
    }
    func updateNSView(_ view: VZVirtualMachineView, context: Context) {
        view.virtualMachine = virtualMachine
    }
}
