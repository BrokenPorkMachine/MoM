import Foundation

@main
struct ConnectivityTests {
    static func main() throws {
        var count = 0
        func check(_ result: @autoclosure () -> Bool, _ description: String) {
            precondition(result(), "FAILED: \(description)")
            count += 1
        }
        func rejects(_ operation: () throws -> Void, _ description: String) {
            do { try operation(); fatalError("Expected rejection: \(description)") }
            catch { count += 1 }
        }
        let fm = FileManager.default
        let scratch = fm.temporaryDirectory.appendingPathComponent("VB-\(UUID().uuidString)")
        try fm.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: scratch) }
        let vm = scratch.appendingPathComponent("TestVM")
        let share = scratch.appendingPathComponent("Shared")
        try fm.createDirectory(at: vm, withIntermediateDirectories: true)
        try fm.createDirectory(at: share, withIntermediateDirectories: true)
        try VMConnectivityPolicy.verify(.default, vmFolder: vm)
        count += 1
        var settings = VMConnectivitySettings.default
        settings.networkMode = .disconnected
        try VMConnectivityPolicy.verify(settings, vmFolder: vm)
        count += 1
        settings.networkMode = .bridged
        settings.bridgedInterfaceID = "en0"
        rejects({ try VMConnectivityPolicy.verify(settings, vmFolder: vm, validInterfaces: ["en0"]) }, "bridging disabled for release")
        settings.networkMode = .nat
        settings.sharedFolderPath = "relative"
        rejects({ try VMConnectivityPolicy.verify(settings, vmFolder: vm) }, "relative share")
        settings.sharedFolderPath = "/dev"
        rejects({ try VMConnectivityPolicy.verify(settings, vmFolder: vm) }, "raw device directory")
        settings.sharedFolderPath = "/dev/disk0"
        rejects({ try VMConnectivityPolicy.verify(settings, vmFolder: vm) }, "device share")
        settings.sharedFolderPath = scratch.path
        rejects({ try VMConnectivityPolicy.verify(settings, vmFolder: vm) }, "VM ancestor share")
        settings.sharedFolderPath = vm.path
        rejects({ try VMConnectivityPolicy.verify(settings, vmFolder: vm) }, "VM folder share")
        settings.sharedFolderPath = vm.appendingPathComponent("anything").path
        rejects({ try VMConnectivityPolicy.verify(settings, vmFolder: vm) }, "VM child share")
        settings.sharedFolderPath = "/"
        rejects({ try VMConnectivityPolicy.verify(settings, vmFolder: vm) }, "root share")
        settings.sharedFolderPath = scratch.appendingPathComponent("not-exists").path
        rejects({ try VMConnectivityPolicy.verify(settings, vmFolder: vm) }, "nonexistent share")
        settings.sharedFolderPath = share.path
        settings.guestToolsEnabled = true
        try VMConnectivityPolicy.verify(settings, vmFolder: vm)
        count += 1
        try VMConnectivityStore.save(settings, to: vm)
        let loaded = try VMConnectivityStore.load(from: vm)
        check(loaded == settings, "profile roundtrip")
        check(VMConnectivityPolicy.stableMAC(for: UUID(uuidString: "00000000-0000-0000-0000-000000000000")!) == "02:00:00:00:00:00", "stable MAC")
        let mac = VMConnectivityPolicy.stableMAC(for: UUID())
        check(mac.split(separator: ":").count == 6, "mac length")
        try HostGuestExchange.createIfNeeded(in: vm)
        try HostGuestExchange.send("hello from host", from: "host", in: vm)
        try HostGuestExchange.send("hello from guest", from: "guest", in: vm)
        check(HostGuestExchange.receive(for: "guest", in: vm).first?.body == "hello from host", "host message")
        check(HostGuestExchange.receive(for: "host", in: vm).first?.body == "hello from guest", "guest message")
        rejects({ try HostGuestExchange.send(String(repeating: "A", count: 16_385), from: "guest", in: vm) }, "message size")
        rejects({ try HostGuestExchange.send("", from: "guest", in: vm) }, "empty message")
        rejects({ try HostGuestExchange.send("bad origin", from: "root", in: vm) }, "invalid origin")
        let hostToGuest = HostGuestExchange.root(for: vm).appendingPathComponent("host-to-guest")
        try fm.removeItem(at: hostToGuest)
        try fm.createSymbolicLink(at: hostToGuest, withDestinationURL: share)
        rejects({ try HostGuestExchange.send("redirect attempt", from: "host", in: vm) }, "reject symlinked exchange component")
        try fm.removeItem(at: hostToGuest)
        try fm.createDirectory(at: hostToGuest, withIntermediateDirectories: false)
        let heartbeat = HostGuestExchange.root(for: vm).appendingPathComponent("heartbeat.json")
        try Data(repeating: 0x41, count: 4_097).write(to: heartbeat)
        check(HostGuestExchange.guestHeartbeat(in: vm) == nil, "reject oversized guest heartbeat")
        let file = share.appendingPathComponent("file.txt")
        try "shared file data".write(to: file, atomically: true, encoding: .utf8)
        let uploaded = try HostGuestExchange.stageFile(file, from: "host", in: vm)
        check(fm.fileExists(atPath: uploaded.path), "file staged")
        check(uploaded.deletingLastPathComponent().lastPathComponent == "host-files", "file direction")
        check(uploaded.lastPathComponent != file.lastPathComponent, "file name randomized")
        print("PASS: \(count) network, share, profile, and guest/host exchange assertions")
    }
}
