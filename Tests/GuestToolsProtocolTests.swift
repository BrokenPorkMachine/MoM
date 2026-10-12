import Foundation

@main
struct GuestToolsProtocolTests {
    static func main() throws {
        var count = 0
        func check(_ condition: @autoclosure () throws -> Bool, _ description: String) throws {
            let valid = try condition()
            precondition(valid, "FAIL: \(description)")
            count += 1
        }
        func reject(_ test: () throws -> Void, _ description: String) {
            do { try test(); fatalError("Not rejected: \(description)") }
            catch { count += 1 }
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("VBTools-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let exchange = root.appendingPathComponent("Exchange")
        try FileManager.default.createDirectory(at: exchange, withIntermediateDirectories: true)
        for name in ["host-files", "guest-files"] {
            try FileManager.default.createDirectory(at: exchange.appendingPathComponent(name), withIntermediateDirectories: true)
        }
        try VBGuestToolsTransport.prepare(root: exchange)
        let requestsPath = exchange.appendingPathComponent("requests")
        try FileManager.default.removeItem(at: requestsPath)
        try FileManager.default.createSymbolicLink(at: requestsPath, withDestinationURL: root)
        reject({ try VBGuestToolsTransport.storeRecord(["sentinel": "x"], root: exchange, directory: "requests", id: UUID()) }, "reject symlinked guest tools directory")
        try FileManager.default.removeItem(at: requestsPath)
        try FileManager.default.createDirectory(at: requestsPath, withIntermediateDirectories: false)
        let abc = VBSHA256.hex(VBSHA256.digest(Data("abc".utf8)))
        try check(abc == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad", "sha256 test vector")
        let million = Data(repeating: 0x61, count: 1_000_000)
        try check(VBSHA256.hex(VBSHA256.digest(million)) == "cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0", "SHA-256 million-byte reference vector")
        let boundaryData = Data((0..<1025).map { UInt8(truncatingIfNeeded: $0) })
        for stride in [1, 7, 55, 63, 64, 65, 128, 511] {
            var digest = VBSHA256()
            for offset in Swift.stride(from: 0, to: boundaryData.count, by: stride) {
                digest.update(boundaryData.subdata(in: offset..<min(offset + stride, boundaryData.count)))
            }
            try check(digest.finish() == VBSHA256.digest(boundaryData), "streaming SHA matches across block boundaries")
        }
        let key = Data(0..<32)
        try check(try VBPairing.mac(key: key, data: Data("auth test".utf8)) == "1913d6bc3f6939f49386c3e14de795cfa55e0d2aa512cae8d451c7df5f397043", "hmac test vector")
        try check(VBPairing.constantTimeEqual("abc", "abc"), "equal MAC")
        try check(!VBPairing.constantTimeEqual("abc", "abd"), "wrong MAC")
        try check(!VBPairing.constantTimeEqual("abc", "ab"), "short MAC")
        try check(try VBPairing.fromHex(VBSHA256.hex(Array(key))) == key, "hex parse")
        reject({ _ = try VBPairing.fromHex("00") }, "invalid hex size")
        let keyURL = root.appendingPathComponent("pairing.key")
        try VBPairing.store(key, to: keyURL)
        try check(try VBPairing.load(keyURL) == key, "pairing key save")
        reject({ try VBPairing.store(key, to: keyURL) }, "refuse overwriting key")
        _ = try VBPairing.createHostKey(root)
        let rotated = try VBPairing.rotateHostKey(root)
        try check(rotated.count == 32 && rotated != key, "pairing key rotation generated new secret")
        try check(try VBPairing.load(VBPairing.hostKeyPath(root)) == rotated, "pairing key rotation persisted")
        try check(try VBPairing.secureRandomKey().count == 32, "secure random")
        let request = try VBGuestRequest.create(.ping, key: key)
        try request.verify(key: key)
        count += 1
        reject({ try request.verify(key: Data(repeating: 9, count: 32)) }, "tampered request key")
        reject({ try request.verify(key: key, now: Date().addingTimeInterval(200)) }, "expired")
        let overflowRequest = VBGuestRequest(version: 2, id: UUID(), milliseconds: Int64.max, action: .ping, authentication: "")
        reject({ try overflowRequest.verify(key: key) }, "extreme request timestamp")
        let reply = try VBGuestReply.create(for: request, detail: "pong", key: key)
        try reply.verify(for: request, key: key)
        count += 1
        reject({ try reply.verify(for: request, key: Data(repeating: 1, count: 32)) }, "wrong reply key")
        reject({ try reply.verify(for: try VBGuestRequest.create(.status, key: key), key: key) }, "wrong request ID")
        let overflowReply = VBGuestReply(version: 2, id: request.id, milliseconds: Int64.min, detail: "pong", authentication: "")
        reject({ try overflowReply.verify(for: request, key: key) }, "extreme reply timestamp")
        try VBGuestToolsTransport.offerClipboard("guest clipboard", origin: "guest", root: exchange)
        try check(VBGuestToolsTransport.latestClipboard(for: "host", root: exchange)?.text == "guest clipboard", "clipboard host incoming")
        try VBGuestToolsTransport.offerClipboard("host clipboard", origin: "host", root: exchange)
        try check(VBGuestToolsTransport.latestClipboard(for: "guest", root: exchange)?.text == "host clipboard", "clipboard guest incoming")
        reject({ try VBGuestToolsTransport.offerClipboard("bad", origin: "root", root: exchange) }, "clipboard origin")
        reject({ try VBGuestToolsTransport.offerClipboard(String(repeating: "x", count: 65_537), origin: "host", root: exchange) }, "clipboard cap")
        let queued = try VBGuestToolsTransport.queueRequest(.status, root: exchange, key: key)
        var seen = Set<UUID>()
        try check(VBGuestToolsTransport.serveRequests(root: exchange, key: key, seen: &seen, hostname: "guestvm") == 1, "serve one authenticated request")
        try check(VBGuestToolsTransport.serveRequests(root: exchange, key: key, seen: &seen, hostname: "guestvm") == 0, "no replay in same session")
        try check(VBGuestToolsTransport.verifiedReplies(root: exchange, key: key).first?.id == queued.id, "verified reply")
        let hostile = VBGuestRequest(version: 2, id: UUID(), milliseconds: Int64(Date().timeIntervalSince1970 * 1000), action: .ping, authentication: "invalid")
        try VBGuestToolsTransport.storeRecord(hostile, root: exchange, directory: "requests", id: hostile.id)
        try check(VBGuestToolsTransport.serveRequests(root: exchange, key: key, seen: &seen, hostname: "guestvm") == 0, "reject forged requests")
        let source = root.appendingPathComponent("sample.txt")
        try Data(repeating: 0x4f, count: 300_000).write(to: source)
        var steps: [Double] = []
        let receipt = try VBGuestToolsTransport.stageFile(source, origin: "host", root: exchange, key: key) { steps.append($0) }
        try check(receipt.bytes == 300_000, "receipt bytes")
        try check(steps.count >= 3 && steps.last == 1 && steps.allSatisfy { $0 > 0 && $0 <= 1 }, "progress monotonic bounded")
        let finalFile = exchange.appendingPathComponent("host-files/\(receipt.filename)")
        try check(try VBGuestToolsTransport.verifyFile(finalFile, against: receipt), "hash verified")
        try check(VBGuestToolsTransport.verifiedTransfers(origin: "host", root: exchange, key: key).first?.id == receipt.id, "authenticated transfer listing")
        try check(VBGuestToolsTransport.verifiedTransfers(origin: "host", root: exchange, key: Data(repeating: 7, count: 32)).isEmpty, "wrong-key transfer listing rejected")
        let destination = root.appendingPathComponent("received", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: false)
        let receivedURL = try VBGuestToolsTransport.receiveTransfer(id: receipt.id, origin: "host", root: exchange, key: key, destination: destination)
        try check(try Data(contentsOf: receivedURL) == Data(repeating: 0x4f, count: 300_000), "verified receive streaming")
        try Data("tampered".utf8).write(to: finalFile)
        try check(try !VBGuestToolsTransport.verifyFile(finalFile, against: receipt), "tamper detected")
        reject({ _ = try VBGuestToolsTransport.stageFile(source, origin: "admin", root: exchange, key: key) }, "invalid transfer origin")
        let large = root.appendingPathComponent("large.bin")
        let file = FileManager.default.createFile(atPath: large.path, contents: Data())
        try check(file, "create oversized fixture")
        let h = try FileHandle(forWritingTo: large)
        try h.truncate(atOffset: 64 * 1024 * 1024 + 1)
        try h.close()
        reject({ _ = try VBGuestToolsTransport.stageFile(large, origin: "host", root: exchange, key: key) }, "oversize transfer")
        print("PASS: \(count) SHA, pairing, authenticated request, clipboard and transfer assertions")
    }
}
