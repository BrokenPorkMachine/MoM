import SwiftUI
import Virtualization

/// Keep the view linked to the live VM; do not attempt to recreate it during redraws.
struct VMConsoleView: NSViewRepresentable {
    let virtualMachine: VZVirtualMachine?
    func makeNSView(context: Context) -> VZVirtualMachineView {
        let view = VZVirtualMachineView()
        view.capturesSystemKeys = true
        view.virtualMachine = virtualMachine
        return view
    }
    func updateNSView(_ view: VZVirtualMachineView, context: Context) {
        view.virtualMachine = virtualMachine
    }
}
