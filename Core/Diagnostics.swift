import Foundation
import OSLog

enum Diagnostics {
    static let logger = Logger(subsystem: "ca.zensoftware.VolumeBoot", category: "runtime")
    struct Event: Codable {
        let timestamp: Date
        let category: String
        let message: String
    }
    private static let lock = NSLock()
    private static var events: [Event] = []
    private static let limit = 500

    static func record(_ message: String, category: String = "runtime") {
        let event = Event(timestamp: Date(), category: category, message: redact(message))
        logger.info("\(event.message, privacy: .public)")
        lock.lock()
        events.append(event)
        if events.count > limit { events.removeFirst(events.count - limit) }
        lock.unlock()
    }

    static func snapshot() -> [Event] {
        lock.lock(); defer { lock.unlock() }
        return events
    }

    /// Writes only bounded, redacted events to a user-selected support file.
    static func export(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(snapshot()).write(to: url, options: .atomic)
    }

    private static func redact(_ message: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return message.replacingOccurrences(of: home, with: "<USER_HOME>")
            .replacingOccurrences(of: ".guesttools-pairing-key", with: "<PAIRING_KEY>")
            .replacingOccurrences(of: "pairing.key", with: "<PAIRING_KEY>")
    }
}
