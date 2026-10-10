import Foundation
import OSLog

enum Diagnostics {
    static let logger = Logger(subsystem: "ca.zensoftware.VolumeBoot", category: "runtime")
    static func record(_ message: String) { logger.info("\(message, privacy: .public)") }
}
