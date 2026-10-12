import Foundation

@main enum VMBackendTrustTests {
    static func main() throws {
        var checks = 0
        func check(_ condition: Bool, _ message: String) {
            precondition(condition, message); checks += 1
        }

        let root = FileManager.default.temporaryDirectory.appendingPathComponent("VMBackendTrust-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false,
                                                attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: root) }
        let trustFile = root.appendingPathComponent("approvals.json")
        let store = VMBackendExecutableTrustStore(fileURL: trustFile)
        let qemu = try VMBackendExecutableTrustStore.inspect(kind: .qemu, path: "/usr/bin/true")
        check(qemu.path.hasPrefix("/"), "canonical absolute path")
        check(qemu.sha256.count == 64, "SHA-256 fingerprint")
        check(try !store.isApproved(qemu), "new executable is untrusted")
        try store.approve(qemu, persistently: false)
        check(try store.isApproved(qemu), "allow-once grants in-memory approval")
        check(try !VMBackendExecutableTrustStore(fileURL: trustFile).isApproved(qemu), "allow-once does not persist")
        try store.approve(qemu, persistently: true)
        check(try VMBackendExecutableTrustStore(fileURL: trustFile).isApproved(qemu), "persistent trust survives reload")

        let changed = VMBackendExecutableIdentity(kind: qemu.kind, path: qemu.path,
                                                   sha256: String(repeating: "0", count: 64))
        check(try !store.isApproved(changed), "changed executable contents require new approval")
        do {
            _ = try VMBackendExecutableTrustStore.inspect(kind: .qemu, path: "relative/qemu")
            fatalError("relative executable accepted")
        } catch VMBackendTrustError.invalidExecutable { checks += 1 }
        let script = root.appendingPathComponent("fake-qemu")
        try Data("#!/bin/sh\necho QEMU emulator version 99.0.0\n".utf8).write(to: script)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
        do {
            _ = try VMBackendExecutableTrustStore.inspect(kind: .qemu, path: script.path)
            fatalError("script backend executable accepted")
        } catch VMBackendTrustError.invalidExecutable { checks += 1 }

        _ = try VMBackendVersion.qemu("QEMU emulator version 9.2.0 (Homebrew)")
        _ = try VMBackendVersion.qemu("QEMU emulator version 10.0.1")
        _ = try VMBackendVersion.swtpm("TPM emulator version 0.10.1, Copyright (c) 2014-2022 IBM Corp. and others")
        do {
            _ = try VMBackendVersion.qemu("QEMU emulator version 9.1.3")
            fatalError("QEMU below 9.2 accepted")
        } catch VMBackendTrustError.unsupportedQEMUVersion { checks += 1 }
        do {
            _ = try VMBackendVersion.qemu("not a QEMU version")
            fatalError("unrecognized QEMU version accepted")
        } catch VMBackendTrustError.versionProbeFailed { checks += 1 }
        do {
            _ = try VMBackendVersion.swtpm("not a swtpm version")
            fatalError("unrecognized swtpm version accepted")
        } catch VMBackendTrustError.versionProbeFailed { checks += 1 }
        print("VM backend executable trust tests PASS: \(checks) checks")
    }
}
