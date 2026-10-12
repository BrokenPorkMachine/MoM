import Foundation
#if canImport(AppKit)
import AppKit
#endif

/// Runs *inside* a trusted macOS guest. No arbitrary or remote shell execution.
struct VBGuestAgent {
    static func root() throws -> URL {
        let path = ProcessInfo.processInfo.environment["VOLUMEBOOT_EXCHANGE"] ?? "/Volumes/My Shared Files/Exchange"
        let url = URL(fileURLWithPath: path, isDirectory: true)
        guard FileManager.default.fileExists(atPath: url.appendingPathComponent("host-to-guest").path) else {
            throw NSError(domain: "VolumeBoot.GuestAgent", code: 1, userInfo: [NSLocalizedDescriptionKey: "Exchange folder not mounted at \(path)"])
        }
        return url
    }
    static func keyPath() -> URL {
        if let override = ProcessInfo.processInfo.environment["VOLUMEBOOT_GUEST_KEY_FILE"] {
            return URL(fileURLWithPath: override)
        }
        return VBPairing.guestKeyPath()
    }
    static func main() throws {
        let args = Array(CommandLine.arguments.dropFirst())
        guard let action = args.first else {
            print("Usage: volumeboot-guest-agent status | serve | poll-once | pair <secret> | send <text> | inbox | push <file> | files | receive <id> <folder> | clipboard-send [text] | clipboard-peek | clipboard-import")
            return
        }
        if action == "pair" {
            guard args.count == 2 else { throw VBToolsError.invalidKey }
            try VBPairing.store(try VBPairing.fromHex(args[1]), to: keyPath())
            print("Paired. Secret stored outside Exchange with owner-only permissions.")
            return
        }
        let exchange = try root()
        try VBGuestToolsTransport.prepare(root: exchange)
        func heartbeat() throws {
            let status = VBGuestHeartbeat(protocolVersion: 2, timestamp: Date(), hostname: ProcessInfo.processInfo.hostName,
                                           operatingSystem: ProcessInfo.processInfo.operatingSystemVersionString)
            try JSONEncoder().encode(status).write(to: exchange.appendingPathComponent("heartbeat.json"), options: .atomic)
        }
        switch action {
        case "status":
            try heartbeat(); print("Guest heartbeat published")
        case "serve", "poll-once":
            let key = try? VBPairing.load(keyPath())
            var seen = Set<UUID>()
            func cycle() throws {
                try heartbeat()
                if let key {
                    let count = VBGuestToolsTransport.serveRequests(root: exchange, key: key, seen: &seen,
                                                                 hostname: ProcessInfo.processInfo.hostName)
                    if count > 0 { print("Serviced \(count) authenticated guest-tool request(s)") }
                }
            }
            try cycle()
            if action == "serve" {
                print("Guest tools active, no network listener, no remote command execution. Ctrl+C to stop.")
                while true { Thread.sleep(forTimeInterval: 5); try cycle() }
            }
        case "send":
            guard args.count > 1 else { throw VBToolsError.malformedRecord }
            let body = args.dropFirst().joined(separator: " ")
            guard !body.isEmpty && body.utf8.count <= HostGuestExchange.maxMessageBytes else { throw VBToolsError.tooLarge }
            try HostGuestExchange.send(body, from: "guest", in: exchange.deletingLastPathComponent())
            print("Guest message queued")
        case "inbox":
            HostGuestExchange.receive(for: "guest", in: exchange.deletingLastPathComponent())
                .forEach { print("\($0.timestamp): \($0.body)") }
        case "push":
            guard args.count == 2 else { throw VBToolsError.malformedRecord }
            let key = try VBPairing.load(keyPath())
            let receipt = try VBGuestToolsTransport.stageFile(URL(fileURLWithPath: args[1]), origin: "guest", root: exchange, key: key) { fraction in
                fputs("\rStaging: \(Int(fraction * 100))%", stderr)
            }
            print("\nStaged \(receipt.filename) sha256=\(receipt.sha256)")
        case "files":
            let key = try VBPairing.load(keyPath())
            for transfer in VBGuestToolsTransport.verifiedTransfers(origin: "host", root: exchange, key: key) {
                print("\(transfer.id) \(transfer.receipt.originalName) (\(transfer.receipt.bytes) bytes, sha256=\(transfer.receipt.sha256))")
            }
        case "receive":
            guard args.count == 3, let id = UUID(uuidString: args[1]) else { throw VBToolsError.malformedRecord }
            let key = try VBPairing.load(keyPath())
            let saved = try VBGuestToolsTransport.receiveTransfer(id: id, origin: "host", root: exchange, key: key,
                destination: URL(fileURLWithPath: args[2], isDirectory: true))
            print("Verified and saved \(saved.lastPathComponent)")
        case "clipboard-send":
            let text: String
            if args.count > 1 { text = args.dropFirst().joined(separator: " ") }
            else {
                #if canImport(AppKit)
                guard let data = NSPasteboard.general.string(forType: .string) else { throw VBToolsError.malformedRecord }
                text = data
                #else
                throw VBToolsError.malformedRecord
                #endif
            }
            try VBGuestToolsTransport.offerClipboard(text, origin: "guest", root: exchange)
            print("Clipboard offer queued. Host must explicitly import it.")
        case "clipboard-peek", "clipboard-import":
            guard let offer = VBGuestToolsTransport.latestClipboard(for: "guest", root: exchange) else {
                print("No host clipboard offer"); return
            }
            if action == "clipboard-peek" { print(offer.text) }
            else {
                #if canImport(AppKit)
                NSPasteboard.general.clearContents()
                guard NSPasteboard.general.setString(offer.text, forType: .string) else { throw VBToolsError.malformedRecord }
                print("Imported host offer into guest clipboard")
                #else
                print(offer.text)
                #endif
            }
        default: throw VBToolsError.malformedRecord
        }
    }
}

try VBGuestAgent.main()
