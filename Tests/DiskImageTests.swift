import Foundation
#if canImport(Virtualization)
import Virtualization
#endif

@main
struct DiskImageTests {
    static func main() throws {
        var count = 0
        func check(_ result: @autoclosure () -> Bool, _ message: String) {
            precondition(result(), "FAILED: \(message)")
            count += 1
        }
        func rejects(_ operation: () throws -> Void, _ message: String) {
            do { try operation(); fatalError("Expected rejection: \(message)") }
            catch { count += 1 }
        }
        let fm = FileManager.default
        let scratch = fm.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("VB-Disks-\(UUID())")
        try fm.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: scratch) }
        let disk = scratch.appendingPathComponent("Storage.raw")
        let image = try VMDiskImageStore.create(at: disk, sizeGiB: 1)
        check(image.sizeBytes == VMDiskImageStore.gibibyte, "logical capacity")
        check(image.allocatedBytes < image.sizeBytes, "sparse creation")
        let marker = Data("guest partition data".utf8)
        let writer = try FileHandle(forWritingTo: disk)
        try writer.write(contentsOf: marker)
        try writer.close()
        rejects({ try VMDiskImageStore.create(at: disk, sizeGiB: 2) }, "existing image never overwritten")
        rejects({ try VMDiskImageStore.create(at: scratch.appendingPathComponent("x.img"), sizeGiB: 0) }, "zero capacity")
        rejects({ try VMDiskImageStore.create(at: scratch.appendingPathComponent("x.img"), sizeGiB: 2049) }, "capacity limit")
        rejects({ _ = try VMDiskImageStore.inspect(at: URL(fileURLWithPath: "/dev/disk0")) }, "physical device")
        rejects({ try VMDiskImageStore.create(at: scratch.appendingPathComponent("x.dmg"), sizeGiB: 1) }, "unsupported container")
        let link = scratch.appendingPathComponent("Alias.img")
        try fm.createSymbolicLink(at: link, withDestinationURL: disk)
        rejects({ try VMDiskImageStore.grow(at: link, toGiB: 2) }, "symlink growth")
        rejects({ try VMDiskImageStore.delete(at: link) }, "symlink deletion")
        let hardlink = scratch.appendingPathComponent("Hardlink.img")
        try fm.linkItem(at: disk, to: hardlink)
        rejects({ try VMDiskImageStore.grow(at: disk, toGiB: 2) }, "hardlinked image growth")
        rejects({ try VMDiskImageStore.delete(at: disk) }, "hardlinked image deletion")
        try fm.removeItem(at: hardlink)
        do {
            let lease = try VMDiskImageLease(url: disk)
            rejects({ try VMDiskImageStore.grow(at: disk, toGiB: 2) }, "active session growth")
            rejects({ try VMDiskImageStore.delete(at: disk) }, "active session deletion")
            rejects({ _ = try VMDiskImageLease(url: disk) }, "second VM cannot use leased image")
            #if canImport(Virtualization)
            // Confirm our advisory session lock is compatible with the native attachment.
            let attachment = try VZDiskImageStorageDeviceAttachment(url: disk, readOnly: false)
            check(attachment.url == disk, "VZ attachment accepts leased image")
            #endif
            withExtendedLifetime(lease) {}
        }
        let grown = try VMDiskImageStore.grow(at: disk, toGiB: 2)
        check(grown.sizeBytes == 2 * VMDiskImageStore.gibibyte, "grown capacity")
        let reader = try FileHandle(forReadingFrom: disk)
        let preserved = try reader.read(upToCount: marker.count)
        check(preserved == marker, "growth preserves guest bytes")
        try reader.seek(toOffset: grown.sizeBytes - 512)
        let zeroes = try reader.read(upToCount: 512)
        check(zeroes == Data(repeating: 0, count: 512), "new space reads as zeros")
        try reader.close()
        rejects({ try VMDiskImageStore.grow(at: disk, toGiB: 1) }, "shrink rejected")
        rejects({ try VMDiskImageStore.grow(at: disk, toGiB: 2) }, "same capacity rejected")
        let malformed = scratch.appendingPathComponent("Malformed.img")
        try Data([1, 2, 3]).write(to: malformed)
        rejects({ _ = try VMDiskImageStore.inspect(at: malformed) }, "unaligned image")
        let bundle = scratch.appendingPathComponent("MacVM")
        try fm.createDirectory(at: bundle, withIntermediateDirectories: false)
        let boot = scratch.appendingPathComponent("macOS.img")
        try VMDiskImageStore.create(at: boot, sizeGiB: 64)
        var settings = VMHardwareSettings.default
        settings.bootDiskPath = boot.path
        settings.additionalDisks = [VMAdditionalDisk(path: disk.path)]
        settings.capturesMouseOnClick = false
        settings.inputReleaseShortcut = .controlCommandG
        try VMHardwarePolicy.verify(settings, vmFolder: bundle)
        try VMHardwareStore.save(settings, to: bundle)
        let loaded = try VMHardwareStore.load(from: bundle)
        check(loaded == settings, "boot image and input settings persist")
        settings.additionalDisks.append(VMAdditionalDisk(path: boot.path))
        rejects({ try VMHardwarePolicy.verify(settings, vmFolder: bundle) }, "boot image cannot also be secondary")
        settings.additionalDisks = []
        settings.bootDiskPath = disk.path
        rejects({ try VMHardwarePolicy.verify(settings, vmFolder: bundle) }, "boot disk minimum")
        let legacy = Data(#"{"version":1,"cpuCount":4,"memoryGiB":8,"capturesSystemKeys":false}"#.utf8)
        let decoded = try JSONDecoder().decode(VMHardwareSettings.self, from: legacy)
        check(decoded.bootDiskPath == nil && decoded.capturesMouseOnClick, "legacy defaults")
        check(decoded.inputReleaseShortcut == .controlOptionEscape && !decoded.capturesSystemKeys, "legacy input flags retained")
        let shortcuts: [(VMInputReleaseShortcut, UInt16, Bool, Bool, Bool)] = [
            (.controlOptionEscape, 53, true, true, false), (.controlCommandG, 5, true, false, true),
            (.optionCommandG, 5, false, true, true)
        ]
        for (shortcut, key, control, option, command) in shortcuts {
            check(shortcut.matches(keyCode: key, control: control, option: option, command: command, shift: false), "release shortcut")
            check(!shortcut.matches(keyCode: key, control: control, option: option, command: command, shift: true), "extra modifier not intercepted")
            check(!shortcut.matches(keyCode: 0, control: control, option: option, command: command, shift: false), "other guest keys not intercepted")
        }
        try VMDiskImageStore.delete(at: disk)
        check(!fm.fileExists(atPath: disk.path), "deletion removes image")
        check(fm.fileExists(atPath: boot.path), "other images unaffected")
        print("PASS: \(count) disk lifecycle, native attachment, legacy profile, and release hotkey assertions")
    }
}
