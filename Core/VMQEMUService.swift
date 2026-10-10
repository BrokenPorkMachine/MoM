import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

enum VMQEMUPlan {
    static func arguments(folder: URL, record: ManagedVMManifest, hardware: VMHardwareSettings,
                          connectivity: VMConnectivitySettings, tpmSocket: URL,
                          accelerator: String = "hvf", display: String = "cocoa,zoom-to-fit=on") throws -> [String] {
        guard record.guestOS == .windowsARM, let settings = record.qemu else { throw VMGuestError.invalidState }
        guard connectivity.networkMode != .bridged, connectivity.sharedFolderPath == nil,
              !connectivity.guestToolsEnabled, !hardware.microphoneEnabled else { throw VMGuestError.unsupportedWindowsSettings }
        func json(_ object: [String: Any]) throws -> String {
            String(decoding: try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]), as: UTF8.self)
        }
        func block(_ url: URL, id: String, readOnly: Bool = false) throws -> [String] {
            ["-blockdev", try json(["driver": "raw", "node-name": id, "read-only": readOnly,
                                   "file": ["driver": "file", "filename": url.path]])]
        }
        var args = ["-name", hardware.displayName.isEmpty ? folder.lastPathComponent : hardware.displayName,
                    "-uuid", record.id.uuidString, "-machine", "\(settings.machine),gic-version=3,highmem=off,acpi=on,pflash0=fwcode,pflash1=fwvars",
                    "-accel", accelerator, "-cpu", accelerator == "hvf" ? "host" : "max",
                    "-smp", String(hardware.cpuCount), "-m", "\(hardware.memoryGiB * 1024)",
                    "-nodefaults", "-no-user-config", "-monitor", "none", "-serial", "none", "-qmp", "stdio",
                    "-display", display, "-device", "ramfb", "-device", "qemu-xhci,id=usb",
                    "-device", "usb-kbd,bus=usb.0", "-device", "usb-tablet,bus=usb.0"]
        args += try block(folder.appendingPathComponent("firmware-code.fd"), id: "fwcode", readOnly: true)
        args += try block(folder.appendingPathComponent("firmware-vars.fd"), id: "fwvars")
        args += try block(hardware.bootDiskURL(in: folder), id: "bootdisk")
        args += ["-device", "nvme,drive=bootdisk,serial=VolumeBootMain,bootindex=1"]
        for (index, disk) in hardware.additionalDisks.enumerated() {
            let id = "extra\(index)"
            args += try block(URL(fileURLWithPath: disk.path), id: id, readOnly: disk.readOnly)
            args += ["-device", "nvme,drive=\(id),serial=VolumeBootExtra\(index)"]
        }
        if record.state == .installing {
            guard let path = record.installationMediaPath else { throw VMGuestError.invalidISO }
            let iso = URL(fileURLWithPath: path)
            try VMGuestMedia.verifyISO(iso)
            args += try block(iso, id: "installer", readOnly: true)
            args += ["-device", "usb-storage,drive=installer,bus=usb.0,removable=on,bootindex=0"]
        }
        if let path = record.driverMediaPath {
            let iso = URL(fileURLWithPath: path)
            try VMGuestMedia.verifyISO(iso)
            args += try block(iso, id: "drivers", readOnly: true)
            args += ["-device", "usb-storage,drive=drivers,bus=usb.0,removable=on"]
        }
        if connectivity.networkMode == .nat {
            args += ["-netdev", "user,id=net0", "-device", "virtio-net-pci,netdev=net0,mac=\(VMConnectivityPolicy.stableMAC(for: record.id))"]
        }
        if hardware.audioOutputEnabled {
            args += ["-audiodev", "coreaudio,id=audio0", "-device", "intel-hda", "-device", "hda-output,audiodev=audio0"]
        }
        args += ["-chardev", "socket,id=chrtpm,path=\(tpmSocket.path)",
                 "-tpmdev", "emulator,id=tpm0,chardev=chrtpm", "-device", "tpm-tis-device,tpmdev=tpm0"]
        return args
    }
}

@MainActor
final class VMQEMUService {
    private var process: Process?
    private var tpm: Process?
    private var input: Pipe?
    private var output: Pipe?
    private var log: FileHandle?
    private var tpmLog: FileHandle?
    private var temporaryFolder: URL?
    private var imageLeases: [VMDiskImageLease] = []
    private var pendingOutput = Data()
    private var ready = false
    private var sessionID: UUID?
    var onExit: ((String) -> Void)?
    var isRunning: Bool { process != nil }

    func start(folder: URL, record: ManagedVMManifest, hardware: VMHardwareSettings,
               connectivity: VMConnectivitySettings, leases: [VMDiskImageLease],
               accelerator: String = "hvf", display: String = "cocoa,zoom-to-fit=on") async throws {
        guard process == nil, let settings = record.qemu else { throw VMGuestError.invalidState }
        guard FileManager.default.isExecutableFile(atPath: settings.executablePath),
              FileManager.default.isExecutableFile(atPath: settings.swtpmPath) else { throw VMGuestError.missingTool("qemu-system-aarch64 and swtpm") }
        let scratch = URL(fileURLWithPath: "/private/tmp").appendingPathComponent("VBQ-\(UUID())")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: false,
                                               attributes: [.posixPermissions: 0o700])
        temporaryFolder = scratch
        imageLeases = leases
        let socket = scratch.appendingPathComponent("tpm.sock")
        let token = UUID()
        sessionID = token
        do {
            let args = try VMQEMUPlan.arguments(folder: folder, record: record, hardware: hardware,
                connectivity: connectivity, tpmSocket: socket, accelerator: accelerator, display: display)
            try FileManager.default.createDirectory(at: folder.appendingPathComponent("tpm"), withIntermediateDirectories: true,
                                                   attributes: [.posixPermissions: 0o700])
            tpmLog = try makeLog(folder.appendingPathComponent("tpm.log"))
            let emulator = Process()
            emulator.executableURL = URL(fileURLWithPath: settings.swtpmPath)
            emulator.currentDirectoryURL = folder
            emulator.arguments = ["socket", "--tpm2", "--tpmstate", "dir=tpm,mode=0600,lock",
                                  "--ctrl", "type=unixio,path=\(socket.path),mode=0600,terminate", "--flags", "not-need-init"]
            emulator.standardOutput = tpmLog
            emulator.standardError = tpmLog
            try emulator.run()
            tpm = emulator
            for _ in 0..<100 {
                if FileManager.default.fileExists(atPath: socket.path) { break }
                guard emulator.isRunning else { throw failure("Software TPM could not start", folder: folder, filename: "tpm.log") }
                try await Task.sleep(nanoseconds: 50_000_000)
            }
            guard FileManager.default.fileExists(atPath: socket.path) else { throw failure("Software TPM startup timed out", folder: folder, filename: "tpm.log") }
            let vm = Process()
            vm.executableURL = URL(fileURLWithPath: settings.executablePath)
            vm.currentDirectoryURL = folder
            vm.arguments = args
            input = Pipe(); output = Pipe()
            vm.standardInput = input
            vm.standardOutput = output
            log = try makeLog(folder.appendingPathComponent("qemu.log"))
            vm.standardError = log
            output?.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let data = handle.availableData
                if !data.isEmpty { Task { @MainActor [weak self] in self?.receive(data, session: token) } }
            }
            vm.terminationHandler = { [weak self] ended in
                let status = ended.terminationStatus
                Task { @MainActor [weak self] in
                    guard let self, self.sessionID == token else { return }
                    self.cleanup()
                    self.onExit?(status == 0 ? "Windows ARM VM stopped" : "Windows ARM exited (\(status)); inspect qemu.log in the VM folder")
                }
            }
            process = vm
            try vm.run()
            for _ in 0..<200 {
                guard vm.isRunning else { throw failure("Windows VM could not start", folder: folder, filename: "qemu.log") }
                if ready { return }
                try await Task.sleep(nanoseconds: 50_000_000)
            }
            throw failure("QEMU startup timed out", folder: folder, filename: "qemu.log")
        } catch {
            try? await stop()
            cleanup()
            throw error
        }
    }

    func stop() async throws {
        if let process, process.isRunning {
            try? command("quit")
            for _ in 0..<50 {
                if !process.isRunning { break }
                try await Task.sleep(nanoseconds: 100_000_000)
            }
            if process.isRunning {
                process.terminate()
                for _ in 0..<20 {
                    if !process.isRunning { break }
                    try await Task.sleep(nanoseconds: 100_000_000)
                }
                if process.isRunning {
                    kill(process.processIdentifier, SIGKILL)
                    // Keep the image locks until the child has actually exited.
                    await Task.detached { process.waitUntilExit() }.value
                }
            }
        }
        cleanup()
    }

    private func receive(_ data: Data, session: UUID) {
        guard sessionID == session else { return }
        pendingOutput.append(data)
        while let end = pendingOutput.firstIndex(of: 10) {
            let line = Data(pendingOutput[..<end])
            pendingOutput.removeSubrange(...end)
            guard let message = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any] else { continue }
            if message["QMP"] != nil { try? command("qmp_capabilities", id: 1) }
            if message["id"] as? Int == 1, message["error"] == nil { ready = true }
        }
    }

    private func command(_ name: String, id: Int = 2) throws {
        let bytes = try JSONSerialization.data(withJSONObject: ["execute": name, "id": id]) + Data([10])
        try input?.fileHandleForWriting.write(contentsOf: bytes)
    }

    private func cleanup() {
        output?.fileHandleForReading.readabilityHandler = nil
        if let tpm, tpm.isRunning { tpm.terminate() }
        tpm = nil; process = nil; input = nil; output = nil
        try? log?.close(); try? tpmLog?.close()
        log = nil; tpmLog = nil; imageLeases = []
        ready = false; pendingOutput = Data(); sessionID = nil
        if let temporaryFolder { try? FileManager.default.removeItem(at: temporaryFolder) }
        temporaryFolder = nil
    }

    private func makeLog(_ url: URL) throws -> FileHandle {
        if !FileManager.default.fileExists(atPath: url.path) {
            guard FileManager.default.createFile(atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o600]) else {
                throw CocoaError(.fileWriteUnknown)
            }
        }
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: 0)
        return handle
    }

    private func failure(_ message: String, folder: URL, filename: String) -> NSError {
        let tail = (try? String(contentsOf: folder.appendingPathComponent(filename), encoding: .utf8))?.suffix(2000) ?? ""
        return NSError(domain: "VolumeBoot.QEMU", code: 1, userInfo: [NSLocalizedDescriptionKey: "\(message). \(tail)"])
    }
}
