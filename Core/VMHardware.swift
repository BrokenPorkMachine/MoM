import Foundation

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
    var additionalDisks: [VMAdditionalDisk] = []

    static let `default` = VMHardwareSettings()
}

enum VMHardwareError: LocalizedError {
    case unsupportedVersion, invalidCPU, invalidMemory, invalidName, tooManyDisks
    case invalidDisk(String), duplicateDisk, protectedDisk, invalidFolder
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
        var paths = Set<String>()
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
            guard paths.insert(url.path).inserted else { throw VMHardwareError.duplicateDisk }
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
