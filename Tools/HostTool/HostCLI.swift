import Foundation
#if canImport(AppKit)
import AppKit
#endif

/// Explicit, opt-in host operations. No incoming request can execute a shell command.
@main
struct VBHostCLI {
    static func main() throws {
        let args = Array(CommandLine.arguments.dropFirst())
        guard args.count >= 2 else {
            print("Usage: volumeboot-host <vm-folder> status | diagnose | inbox | send <text> | push <file> | guest-files | receive <transfer-id> <folder> | pair-init | pair-rotate | pair-code | ping | request-status | replies | clipboard-send [text] | clipboard-peek | clipboard-import")
            return
        }
        let folder = URL(fileURLWithPath: args[0], isDirectory: true)
        let action = args[1]
        let profile = try VMConnectivityStore.load(from: folder)
        guard profile.guestToolsEnabled else { throw NSError(domain: "VolumeBoot.HostTool", code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Enable guest tools for this VM first"]) }
        let root = HostGuestExchange.root(for: folder)
        try HostGuestExchange.createIfNeeded(in: folder)
        try VBGuestToolsTransport.prepare(root: root)
        switch action {
        case "status", "diagnose":
            let status = HostGuestExchange.guestHeartbeat(in: folder)
            if let status { print("Guest: \(status.hostname), \(status.operatingSystem), last seen: \(status.timestamp)") }
            else { print("No guest heartbeat") }
            if action == "diagnose" {
                print("Network mode: \(profile.networkMode.rawValue) (guest DHCP/internet not implied)")
                print("Guest heartbeat fresh: \(status.map { abs($0.timestamp.timeIntervalSinceNow) < 30 } ?? false)")
                if let key = try? VBPairing.load(VBPairing.hostKeyPath(folder)) {
                    print("Authenticated responses: \(VBGuestToolsTransport.verifiedReplies(root: root, key: key).count)")
                } else { print("Pairing: not configured") }
            }
        case "inbox":
            for message in HostGuestExchange.receive(for: "host", in: folder) {
                print("\(message.timestamp) \(message.from): \(message.body)")
            }
        case "send":
            guard args.count >= 3 else { throw VBToolsError.malformedRecord }
            try HostGuestExchange.send(args.dropFirst(2).joined(separator: " "), from: "host", in: folder)
            print("Queued host message")
        case "push":
            guard args.count == 3 else { throw VBToolsError.malformedRecord }
            let key = try VBPairing.load(VBPairing.hostKeyPath(folder))
            let receipt = try VBGuestToolsTransport.stageFile(URL(fileURLWithPath: args[2]), origin: "host", root: root, key: key) { fraction in
                fputs("\rStaging: \(Int(fraction * 100))%", stderr)
            }
            print("\nStaged \(receipt.filename) sha256=\(receipt.sha256)")
        case "guest-files":
            let key = try VBPairing.load(VBPairing.hostKeyPath(folder))
            for transfer in VBGuestToolsTransport.verifiedTransfers(origin: "guest", root: root, key: key) {
                print("\(transfer.id) \(transfer.receipt.originalName) (\(transfer.receipt.bytes) bytes, sha256=\(transfer.receipt.sha256))")
            }
        case "receive":
            guard args.count == 4, let id = UUID(uuidString: args[2]) else { throw VBToolsError.malformedRecord }
            let key = try VBPairing.load(VBPairing.hostKeyPath(folder))
            let saved = try VBGuestToolsTransport.receiveTransfer(id: id, origin: "guest", root: root, key: key,
                destination: URL(fileURLWithPath: args[3], isDirectory: true))
            print("Verified and saved \(saved.lastPathComponent)")
        case "pair-init", "pair-rotate", "pair-code":
            let key: Data
            if action == "pair-init" { key = try VBPairing.createHostKey(folder) }
            else if action == "pair-rotate" { key = try VBPairing.rotateHostKey(folder) }
            else { key = try VBPairing.load(VBPairing.hostKeyPath(folder)) }
            print("Pairing key (sensitive; enter manually inside trusted guest): \(VBSHA256.hex(Array(key)))")
        case "ping", "request-status":
            let key = try VBPairing.load(VBPairing.hostKeyPath(folder))
            let request = try VBGuestToolsTransport.queueRequest(action == "ping" ? .ping : .status, root: root, key: key)
            print("Queued authenticated \(request.action.rawValue) id=\(request.id). Run guest agent serve/poll-once and check replies.")
        case "replies":
            let key = try VBPairing.load(VBPairing.hostKeyPath(folder))
            for reply in VBGuestToolsTransport.verifiedReplies(root: root, key: key) { print("\(reply.id): \(reply.detail)") }
        case "clipboard-send":
            let text: String
            if args.count > 2 { text = args.dropFirst(2).joined(separator: " ") }
            else {
                #if canImport(AppKit)
                guard let found = NSPasteboard.general.string(forType: .string) else { throw VBToolsError.malformedRecord }
                text = found
                #else
                throw VBToolsError.malformedRecord
                #endif
            }
            try VBGuestToolsTransport.offerClipboard(text, origin: "host", root: root)
            print("Clipboard offer staged. Guest must explicitly import it.")
        case "clipboard-peek", "clipboard-import":
            guard let offer = VBGuestToolsTransport.latestClipboard(for: "host", root: root) else { print("No guest clipboard offer"); return }
            if action == "clipboard-peek" { print(offer.text) }
            else {
                #if canImport(AppKit)
                NSPasteboard.general.clearContents()
                guard NSPasteboard.general.setString(offer.text, forType: .string) else { throw VBToolsError.malformedRecord }
                print("Imported guest offer into host clipboard")
                #else
                print(offer.text)
                #endif
            }
        default: throw VBToolsError.malformedRecord
        }
    }
}
