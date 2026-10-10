import SwiftUI
import AppKit
import Virtualization

struct VMConsoleView: View {
    let virtualMachine: VZVirtualMachine?
    let hardware: VMHardwareSettings
    @State private var inputCaptured = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button("Capture mouse") { inputCaptured = true }
                    .disabled(virtualMachine == nil || inputCaptured)
                Button("Release mouse") { inputCaptured = false }.disabled(!inputCaptured)
                Text(inputCaptured ? "Mouse captured · \(hardware.inputReleaseShortcut.title) to release" : "Mouse released")
                    .font(.caption).foregroundStyle(.secondary)
            }
            VMConsoleSurface(virtualMachine: virtualMachine, hardware: hardware, inputCaptured: $inputCaptured)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onChange(of: virtualMachine == nil) { _, absent in if absent { inputCaptured = false } }
    }
}

/// Keep the framebuffer linked to the live VM while an overlay gates released input.
private struct VMConsoleSurface: NSViewRepresentable {
    let virtualMachine: VZVirtualMachine?
    let hardware: VMHardwareSettings
    @Binding var inputCaptured: Bool

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeNSView(context: Context) -> ConsoleContainer {
        let container = ConsoleContainer()
        context.coordinator.container = container
        container.overlay.onClick = { [weak coordinator = context.coordinator] in
            guard let coordinator, coordinator.parent.hardware.capturesMouseOnClick else { return }
            coordinator.capture()
        }
        context.coordinator.installMonitors()
        return container
    }

    func updateNSView(_ container: ConsoleContainer, context: Context) {
        context.coordinator.parent = self
        if container.console.virtualMachine !== virtualMachine {
            context.coordinator.release()
            container.console.virtualMachine = virtualMachine
        }
        container.console.automaticallyReconfiguresDisplay = hardware.automaticallyResizeDisplay
        context.coordinator.applyCapture(inputCaptured && virtualMachine != nil)
    }

    static func dismantleNSView(_ container: ConsoleContainer, coordinator: Coordinator) {
        coordinator.release()
        coordinator.removeMonitors()
        container.console.virtualMachine = nil
    }

    @MainActor
    final class Coordinator {
        var parent: VMConsoleSurface
        weak var container: ConsoleContainer?
        private var captured = false
        private var localMonitor: Any?
        private var globalMouseMonitor: Any?
        private var notifications: [NSObjectProtocol] = []

        init(parent: VMConsoleSurface) { self.parent = parent }

        func capture() {
            guard parent.virtualMachine != nil, let window = container?.window, NSApp.isActive, window.isKeyWindow else { return }
            applyCapture(true)
            parent.inputCaptured = true
        }

        func release() {
            applyCapture(false)
            if parent.inputCaptured {
                // Representable updates may trigger release; publish after the current update.
                let binding = parent.$inputCaptured
                DispatchQueue.main.async { binding.wrappedValue = false }
            }
        }

        func applyCapture(_ value: Bool) {
            guard let container else { return }
            let active = value && NSApp.isActive && container.window?.isKeyWindow == true
            captured = active
            container.overlay.isHidden = active
            container.console.capturesSystemKeys = active && parent.hardware.capturesSystemKeys
            if active {
                container.window?.acceptsMouseMovedEvents = true
                if container.window?.firstResponder !== container.console {
                    container.window?.makeFirstResponder(container.console)
                }
                confinePointer()
            } else if container.window?.firstResponder === container.console {
                container.window?.makeFirstResponder(container.overlay)
            }
        }

        func installMonitors() {
            localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown,
                .otherMouseDown, .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]) { [weak self] event in
                guard let self, self.captured else { return event }
                if event.type == .keyDown, self.matchesRelease(event) {
                    self.release()
                    return nil
                }
                if event.type == .leftMouseDown || event.type == .rightMouseDown || event.type == .otherMouseDown {
                    if event.window !== self.container?.window || !self.pointerIsInside() {
                        self.release()
                        return event
                    }
                }
                self.confinePointer()
                return event
            }
            // Mouse-only monitoring requires no global keyboard hook or accessibility grant.
            globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged,
                .rightMouseDragged, .otherMouseDragged]) { [weak self] _ in self?.confinePointer() }
            let center = NotificationCenter.default
            notifications.append(center.addObserver(forName: NSApplication.didResignActiveNotification,
                object: nil, queue: .main) { [weak self] _ in MainActor.assumeIsolated { self?.release() } })
            notifications.append(center.addObserver(forName: NSWindow.didResignKeyNotification,
                object: nil, queue: .main) { [weak self] note in
                    MainActor.assumeIsolated {
                        guard let self, let window = note.object as? NSWindow, window === self.container?.window else { return }
                        self.release()
                    }
                })
        }

        private func matchesRelease(_ event: NSEvent) -> Bool {
            let flags = event.modifierFlags
            return parent.hardware.inputReleaseShortcut.matches(keyCode: event.keyCode,
                control: flags.contains(.control), option: flags.contains(.option),
                command: flags.contains(.command), shift: flags.contains(.shift))
        }

        private func screenRect() -> NSRect? {
            guard let container, let window = container.window, window.isKeyWindow, NSApp.isActive else { return nil }
            return window.convertToScreen(container.console.convert(container.console.bounds, to: nil)).insetBy(dx: 2, dy: 2)
        }

        private func pointerIsInside() -> Bool { screenRect()?.contains(NSEvent.mouseLocation) == true }

        private func confinePointer() {
            guard captured, let rect = screenRect(), rect.width > 0, rect.height > 0,
                  let primary = NSScreen.screens.first else { return }
            let location = NSEvent.mouseLocation
            guard !rect.contains(location) else { return }
            let target = NSPoint(x: min(max(location.x, rect.minX), rect.maxX - 1),
                                 y: min(max(location.y, rect.minY), rect.maxY - 1))
            CGWarpMouseCursorPosition(CGPoint(x: target.x, y: primary.frame.maxY - target.y))
        }

        func removeMonitors() {
            if let localMonitor { NSEvent.removeMonitor(localMonitor) }
            if let globalMouseMonitor { NSEvent.removeMonitor(globalMouseMonitor) }
            notifications.forEach { NotificationCenter.default.removeObserver($0) }
            notifications = []
            localMonitor = nil
            globalMouseMonitor = nil
        }
    }
}

private final class ConsoleContainer: NSView {
    let console = VZVirtualMachineView()
    let overlay = CaptureOverlay()
    override init(frame: NSRect) {
        super.init(frame: frame)
        addSubview(console)
        addSubview(overlay)
        for view in [console, overlay] {
            view.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                view.leadingAnchor.constraint(equalTo: leadingAnchor), view.trailingAnchor.constraint(equalTo: trailingAnchor),
                view.topAnchor.constraint(equalTo: topAnchor), view.bottomAnchor.constraint(equalTo: bottomAnchor)
            ])
        }
    }
    convenience init() { self.init(frame: .zero) }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
}

private final class CaptureOverlay: NSView {
    var onClick: (() -> Void)?
    override var acceptsFirstResponder: Bool { true }
    override func mouseDown(with event: NSEvent) { onClick?() }
    override func rightMouseDown(with event: NSEvent) {}
    override func otherMouseDown(with event: NSEvent) {}
    override func scrollWheel(with event: NSEvent) {}
}
