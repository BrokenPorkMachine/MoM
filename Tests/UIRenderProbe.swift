import SwiftUI
import AppKit

/// A manual preview tool: captures only these test windows, without installer media or real VMs.
@main
struct UIRenderProbe {
    @MainActor
    static func main() throws {
        guard CommandLine.arguments.count == 2 else { fatalError("Pass an output folder") }
        let output = URL(fileURLWithPath: CommandLine.arguments[1])
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("VB-UI-\(UUID())")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: scratch) }
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let fresh = AppModel()
        let loaded = AppModel()
        for (index, guest) in VMGuestOS.allCases.enumerated() {
            let folder = scratch.appendingPathComponent("\(guest.title) Development")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
            try VMDiskImageStore.create(at: folder.appendingPathComponent("disk.img"), sizeGiB: 80)
            var hardware = VMHardwareSettings.default
            hardware.displayName = "\(guest.title) Development"
            hardware.cpuCount = 4; hardware.memoryGiB = 8
            try VMHardwareStore.save(hardware, to: folder)
            let manifest = ManagedVMManifest(version: 3, id: UUID(), createdAt: Date().addingTimeInterval(Double(-index)),
                diskSizeGiB: 80, state: .installed, lastFailure: nil, guestOS: guest)
            try VMRegistry.write(manifest, at: folder)
            if guest == .macOS { loaded.loadHardwareProfile(for: folder) }
        }
        loaded.refreshManagedVMs()
        let disk = scratch.appendingPathComponent("Project storage.img")
        loaded.createDiskImage(at: disk, sizeGiB: 16, asBootDisk: false)
        func render(_ name: String, model: AppModel, width: CGFloat = 1280, height: CGFloat = 860,
                    dark: Bool = false, section: VMWorkspaceSection = .overview) throws {
            let bounds = NSRect(x: 0, y: 0, width: width, height: height)
            let window = NSWindow(contentRect: bounds, styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            app.appearance = window.appearance
            let host = NSHostingView(rootView: DashboardView(initialWorkspaceSection: section).environmentObject(model)
                .environment(\.colorScheme, dark ? .dark : .light))
            host.frame = bounds; window.contentView = host
            window.orderFront(nil)
            RunLoop.current.run(until: Date().addingTimeInterval(0.5))
            host.layoutSubtreeIfNeeded()
            guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { fatalError("No bitmap") }
            window.effectiveAppearance.performAsCurrentDrawingAppearance {
                host.cacheDisplay(in: host.bounds, to: bitmap)
            }
            guard let png = bitmap.representation(using: .png, properties: [:]) else { fatalError("No PNG") }
            try png.write(to: output.appendingPathComponent(name + ".png"))
            window.orderOut(nil); window.close()
        }
        try render("new-vm", model: fresh)
        try render("compact", model: fresh, width: 1000, height: 640)
        try render("overview", model: loaded)
        try render("disks", model: loaded, section: .disks)
        try render("hardware-dark", model: loaded, dark: true, section: .hardware)
        try render("network", model: loaded, section: .network)
        print("Rendered six UI previews in \(output.path)")
    }
}
