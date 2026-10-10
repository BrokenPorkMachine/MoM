import Foundation

enum CompatibilityStatus: String, Codable, Sendable {
    case inspectOnly = "Inspection only"
    case blocked = "Blocked by host safety policy"
    case experimental = "Experimental — not verified"
}

struct CompatibilityVerdict: Codable, Sendable {
    let status: CompatibilityStatus
    let reasons: [String]
}

enum CompatibilityEngine {
    static func inspect(_ device: StorageDevice) -> CompatibilityVerdict {
        if device.isInternal && device.mountPoint == "/" {
            return .init(status: .blocked, reasons: ["Host root volume cannot be attached for writable guest access."])
        }
        return .init(status: .inspectOnly, reasons: [
            "Disk metadata alone does not prove a macOS installation or boot compatibility.",
            "APFS volume-group inspection is not implemented in this scaffold.",
            "Any existing-installation boot attempt requires an expendable clone."
        ])
    }
}
