import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

enum VMWorkspaceLeaseError: LocalizedError {
    case invalidWorkspace, inUse, cannotOpen
    var errorDescription: String? {
        switch self {
        case .invalidWorkspace: return "The VM workspace is not a safe directory."
        case .inUse: return "This VM workspace is already in use by another process."
        case .cannotOpen: return "The VM workspace could not be opened for exclusive use."
        }
    }
}

/// Administrator policy loaded from the managed system location. Missing
/// policy means no additional restriction; present policy is fail-closed.
struct VMManagedPolicy: Codable {
    var allowedStorageRoots: [String] = []
    var maxCPUCount: Int?
    var maxMemoryGiB: Int?
    var allowMicrophone = true
    var allowWritableShares = true
    var allowGuestTools = true
    var allowBridgedNetworking = false
    var allowedExecutablePaths: [String] = []

    static let path = "/Library/Application Support/MacOnMac/policy.json"
    static func load() throws -> VMManagedPolicy {
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: url.path) else { return VMManagedPolicy() }
        return try JSONDecoder().decode(VMManagedPolicy.self, from: Data(contentsOf: url))
    }

    func verifyHardware(_ settings: VMHardwareSettings) throws {
        if let maxCPUCount, settings.cpuCount > maxCPUCount { throw VMHardwareError.invalidCPU }
        if let maxMemoryGiB, settings.memoryGiB > maxMemoryGiB { throw VMHardwareError.invalidMemory }
        guard allowMicrophone || !settings.microphoneEnabled else { throw VMHardwareError.policyDenied("microphone") }
    }
}

/// Cross-process lease for every mutable file in a VM bundle. `flock` releases
/// ownership automatically when the process exits, so a crashed owner does
/// not leave a permanently stale lease file behind.
final class VMWorkspaceLease {
    static let filename = ".workspace.lock"
    private static let mutex = NSLock()
    private static var active: [String: (descriptor: Int32, count: Int)] = [:]
    let folder: URL
    private let key: String
    private let descriptor: Int32

    init(folder: URL) throws {
        let resolved = folder.standardizedFileURL.resolvingSymlinksInPath()
        guard resolved.path != "/", resolved.path != "/dev", !resolved.path.hasPrefix("/dev/"),
              (try? resolved.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else {
            throw VMWorkspaceLeaseError.invalidWorkspace
        }
        self.folder = resolved
        self.key = resolved.path
        Self.mutex.lock()
        if let existing = Self.active[key] {
            Self.active[key] = (existing.descriptor, existing.count + 1)
            self.descriptor = existing.descriptor
            Self.mutex.unlock()
            return
        }
        let path = resolved.appendingPathComponent(Self.filename).path
        let fd = open(path, O_RDWR | O_CREAT | O_NOFOLLOW | O_CLOEXEC, mode_t(0o600))
        guard fd >= 0 else { Self.mutex.unlock(); throw VMWorkspaceLeaseError.cannotOpen }
        var info = stat()
        guard fstat(fd, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG,
              info.st_uid == getuid(), (info.st_mode & 0o077) == 0 else {
            close(fd); Self.mutex.unlock(); throw VMWorkspaceLeaseError.invalidWorkspace
        }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
            close(fd); Self.mutex.unlock(); throw VMWorkspaceLeaseError.inUse
        }
        Self.active[key] = (fd, 1)
        self.descriptor = fd
        Self.mutex.unlock()
    }

    deinit {
        Self.mutex.lock()
        guard let existing = Self.active[key] else { Self.mutex.unlock(); return }
        if existing.count > 1 {
            Self.active[key] = (existing.descriptor, existing.count - 1)
        } else {
            Self.active.removeValue(forKey: key)
            flock(existing.descriptor, LOCK_UN)
            close(existing.descriptor)
        }
        Self.mutex.unlock()
    }
}

enum VMDisplayPreset: String, Codable, CaseIterable, Identifiable {
    case compact, fullHD, retina, wide
    var id: String { rawValue }
    var title: String {
        switch self {
        case .compact: return "1280 × 800"
        case .fullHD: return "1920 × 1080"
        case .retina: return "2560 × 1600"
        case .wide: return "2560 × 1440"
        }
    }
    var width: Int {
        switch self {
        case .compact: return 1280
        case .fullHD: return 1920
        case .retina, .wide: return 2560
        }
    }
    var height: Int {
        switch self {
        case .compact: return 800
        case .fullHD: return 1080
        case .retina: return 1600
        case .wide: return 1440
        }
    }
    var pixelsPerInch: Int { self == .retina ? 220 : 110 }
}

enum VMKeyboardKind: String, Codable, CaseIterable, Identifiable {
    case mac, usb
    var id: String { rawValue }
    var title: String { self == .mac ? "Apple keyboard + USB compatibility" : "USB keyboard" }
}

enum VMPointerKind: String, Codable, CaseIterable, Identifiable {
    case trackpad, mouse
    var id: String { rawValue }
    var title: String { self == .trackpad ? "Multi-touch trackpad" : "USB pointing device" }
}

enum VMInputReleaseShortcut: String, Codable, CaseIterable, Identifiable {
    case controlOptionEscape, controlCommandG, optionCommandG
    var id: String { rawValue }
    var title: String {
        switch self {
        case .controlOptionEscape: return "Control + Option + Escape"
        case .controlCommandG: return "Control + Command + G"
        case .optionCommandG: return "Option + Command + G"
        }
    }
    func matches(keyCode: UInt16, control: Bool, option: Bool, command: Bool, shift: Bool) -> Bool {
        guard !shift else { return false }
        switch self {
        case .controlOptionEscape: return keyCode == 53 && control && option && !command
        case .controlCommandG: return keyCode == 5 && control && command && !option
        case .optionCommandG: return keyCode == 5 && option && command && !control
        }
    }
}

struct VMAdditionalDisk: Codable, Equatable, Identifiable {
    var id = UUID()
    var path: String
    var readOnly = false
}

/// Mutable virtual hardware belongs to a VM, independently of its immutable Mac identity.
/// Missing profiles use the previous release's compute and display defaults.
struct VMHardwareSettings: Codable, Equatable {
    var version = 1
    var displayName = ""
    var cpuCount = 2
    var memoryGiB = 4
    var display: VMDisplayPreset = .compact
    var automaticallyResizeDisplay = true
    var audioOutputEnabled = true
    var microphoneEnabled = false
    var keyboard: VMKeyboardKind = .mac
    var pointer: VMPointerKind = .trackpad
    var capturesSystemKeys = true
    var capturesMouseOnClick = true
    var inputReleaseShortcut: VMInputReleaseShortcut = .controlOptionEscape
    /// Nil preserves the boot disk location used by older VM bundles.
    var bootDiskPath: String?
    var additionalDisks: [VMAdditionalDisk] = []

    static let `default` = VMHardwareSettings()

    init() {}
    private enum CodingKeys: String, CodingKey {
        case version, displayName, cpuCount, memoryGiB, display, automaticallyResizeDisplay
        case audioOutputEnabled, microphoneEnabled, keyboard, pointer, capturesSystemKeys
        case capturesMouseOnClick, inputReleaseShortcut, bootDiskPath, additionalDisks
    }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        version = try values.decodeIfPresent(Int.self, forKey: .version) ?? 1
        displayName = try values.decodeIfPresent(String.self, forKey: .displayName) ?? ""
        cpuCount = try values.decodeIfPresent(Int.self, forKey: .cpuCount) ?? 2
        memoryGiB = try values.decodeIfPresent(Int.self, forKey: .memoryGiB) ?? 4
        display = try values.decodeIfPresent(VMDisplayPreset.self, forKey: .display) ?? .compact
        automaticallyResizeDisplay = try values.decodeIfPresent(Bool.self, forKey: .automaticallyResizeDisplay) ?? true
        audioOutputEnabled = try values.decodeIfPresent(Bool.self, forKey: .audioOutputEnabled) ?? true
        microphoneEnabled = try values.decodeIfPresent(Bool.self, forKey: .microphoneEnabled) ?? false
        keyboard = try values.decodeIfPresent(VMKeyboardKind.self, forKey: .keyboard) ?? .mac
        pointer = try values.decodeIfPresent(VMPointerKind.self, forKey: .pointer) ?? .trackpad
        capturesSystemKeys = try values.decodeIfPresent(Bool.self, forKey: .capturesSystemKeys) ?? true
        capturesMouseOnClick = try values.decodeIfPresent(Bool.self, forKey: .capturesMouseOnClick) ?? true
        inputReleaseShortcut = try values.decodeIfPresent(VMInputReleaseShortcut.self, forKey: .inputReleaseShortcut) ?? .controlOptionEscape
        bootDiskPath = try values.decodeIfPresent(String.self, forKey: .bootDiskPath)
        additionalDisks = try values.decodeIfPresent([VMAdditionalDisk].self, forKey: .additionalDisks) ?? []
    }

    func bootDiskURL(in folder: URL) -> URL {
        bootDiskPath.map { URL(fileURLWithPath: $0) } ?? folder.appendingPathComponent("disk.img")
    }
}

enum VMHardwareError: LocalizedError {
    case unsupportedVersion, invalidCPU, invalidMemory, invalidName, tooManyDisks
    case invalidDisk(String), duplicateDisk, protectedDisk, invalidFolder, policyDenied(String)
    var errorDescription: String? {
        switch self {
        case .unsupportedVersion: return "This hardware profile version is not supported."
        case .invalidCPU: return "Choose a CPU count within this Mac's virtualization limits."
        case .invalidMemory: return "Choose at least 4 GiB of memory within this Mac's virtualization limits."
        case .invalidName: return "Use an instance name of 80 characters or fewer."
        case .tooManyDisks: return "An instance can have up to eight additional disk images."
        case .invalidDisk(let path): return "Select an existing, regular .img or .raw disk image: \(path)"
        case .duplicateDisk: return "The same disk image cannot be attached more than once."
        case .protectedDisk: return "VM bundle files and device nodes cannot be additional disk images."
        case .invalidFolder: return "Select an existing VM directory outside the device tree."
        case .policyDenied(let setting): return "An administrator policy disallows \(setting)."
        }
    }
}

enum VMHardwarePolicy {
    static func verify(_ settings: VMHardwareSettings, vmFolder: URL,
                       cpuRange: ClosedRange<Int> = 2...64, maximumMemoryGiB: Int = 1024) throws {
        guard settings.version == 1 else { throw VMHardwareError.unsupportedVersion }
        guard cpuRange.contains(settings.cpuCount) else { throw VMHardwareError.invalidCPU }
        guard (4...max(4, maximumMemoryGiB)).contains(settings.memoryGiB) else { throw VMHardwareError.invalidMemory }
        guard settings.displayName.count <= 80,
              !settings.displayName.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            throw VMHardwareError.invalidName
        }
        guard settings.additionalDisks.count <= 8 else { throw VMHardwareError.tooManyDisks }
        let bundle = vmFolder.standardizedFileURL.resolvingSymlinksInPath().path
        var identities = Set<String>()
        let bootURL = settings.bootDiskURL(in: vmFolder)
        if let bootPath = settings.bootDiskPath {
            guard bootPath.hasPrefix("/"), !bootPath.hasPrefix(bundle + "/") else { throw VMHardwareError.protectedDisk }
            let boot = try VMDiskImageStore.inspect(at: bootURL)
            guard boot.sizeBytes >= 64 * VMDiskImageStore.gibibyte else { throw VMDiskImageError.invalidSize }
            identities.insert(boot.identity)
        } else if FileManager.default.fileExists(atPath: bootURL.path) {
            let boot = try VMDiskImageStore.inspect(at: bootURL)
            guard boot.sizeBytes >= 64 * VMDiskImageStore.gibibyte else { throw VMDiskImageError.invalidSize }
            identities.insert(boot.identity)
        }
        for disk in settings.additionalDisks {
            guard disk.path.hasPrefix("/") else { throw VMHardwareError.invalidDisk(disk.path) }
            let url = URL(fileURLWithPath: disk.path).standardizedFileURL.resolvingSymlinksInPath()
            guard url.path != "/dev", !url.path.hasPrefix("/dev/"), !url.path.hasPrefix(bundle + "/") else {
                throw VMHardwareError.protectedDisk
            }
            guard ["img", "raw"].contains(url.pathExtension.lowercased()),
                  (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else {
                throw VMHardwareError.invalidDisk(disk.path)
            }
            let image = try VMDiskImageStore.inspect(at: URL(fileURLWithPath: disk.path))
            guard identities.insert(image.identity).inserted else { throw VMHardwareError.duplicateDisk }
        }
    }
}

enum VMHardwareStore {
    static let filename = "hardware.json"
    static func load(from folder: URL) throws -> VMHardwareSettings {
        let file = folder.appendingPathComponent(filename)
        guard FileManager.default.fileExists(atPath: file.path) else { return .default }
        return try JSONDecoder().decode(VMHardwareSettings.self, from: Data(contentsOf: file))
    }
    static func save(_ settings: VMHardwareSettings, to folder: URL) throws {
        let lease = try VMWorkspaceLease(folder: folder)
        defer { withExtendedLifetime(lease) {} }
        let resolved = folder.standardizedFileURL.resolvingSymlinksInPath()
        guard resolved.path != "/dev", !resolved.path.hasPrefix("/dev/"),
              (try? resolved.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else {
            throw VMHardwareError.invalidFolder
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(settings).write(to: folder.appendingPathComponent(filename), options: .atomic)
    }
}
