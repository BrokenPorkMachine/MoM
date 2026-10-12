import Foundation

#if canImport(Security)
import Security
#endif

/// Guest Tools v2. Data-only file protocol transported through the opt-in VirtioFS Exchange.
/// Never put pairing keys inside the guest-visible Exchange directory.
enum VBToolsError: Error, LocalizedError {
    case invalidKey, malformedRecord, invalidOrigin, noPairing, unauthenticated, expired, tooLarge, unsafeFile, retentionQuota
    var errorDescription: String? {
        switch self {
        case .invalidKey: return "Pairing key must contain exactly 32 random bytes"
        case .malformedRecord: return "Invalid guest tools record"
        case .invalidOrigin: return "Unknown guest/host origin"
        case .noPairing: return "Guest tools have not been paired"
        case .unauthenticated: return "Guest tools request signature is invalid"
        case .expired: return "Request expired or timestamp is in the future"
        case .tooLarge: return "Data exceeds guest tools size limit"
        case .unsafeFile: return "Unsafe source or destination file"
        case .retentionQuota: return "Guest tools retention quota is full"
        }
    }
}

// Portable SHA-256 (FIPS 180-4); used to validate transfer receipts and HMAC-SHA256.
// Avoids additional package dependencies for the standalone guest and host utilities.
struct VBSHA256 {
    private static let k: [UInt32] = [
        0x428a2f98,0x71374491,0xb5c0fbcf,0xe9b5dba5,0x3956c25b,0x59f111f1,0x923f82a4,0xab1c5ed5,
        0xd807aa98,0x12835b01,0x243185be,0x550c7dc3,0x72be5d74,0x80deb1fe,0x9bdc06a7,0xc19bf174,
        0xe49b69c1,0xefbe4786,0x0fc19dc6,0x240ca1cc,0x2de92c6f,0x4a7484aa,0x5cb0a9dc,0x76f988da,
        0x983e5152,0xa831c66d,0xb00327c8,0xbf597fc7,0xc6e00bf3,0xd5a79147,0x06ca6351,0x14292967,
        0x27b70a85,0x2e1b2138,0x4d2c6dfc,0x53380d13,0x650a7354,0x766a0abb,0x81c2c92e,0x92722c85,
        0xa2bfe8a1,0xa81a664b,0xc24b8b70,0xc76c51a3,0xd192e819,0xd6990624,0xf40e3585,0x106aa070,
        0x19a4c116,0x1e376c08,0x2748774c,0x34b0bcb5,0x391c0cb3,0x4ed8aa4a,0x5b9cca4f,0x682e6ff3,
        0x748f82ee,0x78a5636f,0x84c87814,0x8cc70208,0x90befffa,0xa4506ceb,0xbef9a3f7,0xc67178f2
    ]
    private var h: [UInt32] = [0x6a09e667,0xbb67ae85,0x3c6ef372,0xa54ff53a,0x510e527f,0x9b05688c,0x1f83d9ab,0x5be0cd19]
    private var buffer: [UInt8] = []
    private var count: UInt64 = 0
    private static func rotate(_ x: UInt32, _ by: UInt32) -> UInt32 { (x >> by) | (x << (32 - by)) }
    private mutating func consume(_ bytes: ArraySlice<UInt8>) {
        var w = [UInt32](repeating: 0, count: 64)
        let block = Array(bytes)
        for i in 0..<16 {
            let j = i * 4
            w[i] = (UInt32(block[j]) << 24) | (UInt32(block[j+1]) << 16) | (UInt32(block[j+2]) << 8) | UInt32(block[j+3])
        }
        for i in 16..<64 {
            let a = w[i-15], b = w[i-2]
            let s0 = Self.rotate(a, 7) ^ Self.rotate(a, 18) ^ (a >> 3)
            let s1 = Self.rotate(b, 17) ^ Self.rotate(b, 19) ^ (b >> 10)
            w[i] = w[i-16] &+ s0 &+ w[i-7] &+ s1
        }
        var v = h
        for i in 0..<64 {
            let s1 = Self.rotate(v[4],6) ^ Self.rotate(v[4],11) ^ Self.rotate(v[4],25)
            let ch = (v[4] & v[5]) ^ (~v[4] & v[6])
            let t1 = v[7] &+ s1 &+ ch &+ Self.k[i] &+ w[i]
            let s0 = Self.rotate(v[0],2) ^ Self.rotate(v[0],13) ^ Self.rotate(v[0],22)
            let maj = (v[0] & v[1]) ^ (v[0] & v[2]) ^ (v[1] & v[2])
            let t2 = s0 &+ maj
            for j in (1...7).reversed() { v[j] = v[j-1] }
            v[4] = v[4] &+ t1
            v[0] = t1 &+ t2
        }
        for i in 0..<8 { h[i] = h[i] &+ v[i] }
    }
    mutating func update(_ data: Data) {
        let bytes = Array(data)
        count &+= UInt64(bytes.count)
        var offset = 0
        if !buffer.isEmpty {
            let taken = min(64 - buffer.count, bytes.count)
            buffer.append(contentsOf: bytes.prefix(taken))
            offset = taken
            if buffer.count == 64 {
                consume(buffer[0..<64])
                buffer.removeAll(keepingCapacity: true)
            }
        }
        // Process blocks in place instead of repeatedly shifting a whole file chunk.
        while bytes.count - offset >= 64 {
            consume(bytes[offset..<(offset + 64)])
            offset += 64
        }
        buffer.append(contentsOf: bytes[offset...])
    }
    mutating func finish() -> [UInt8] {
        let bits = count &* 8
        buffer.append(0x80)
        while buffer.count % 64 != 56 { buffer.append(0) }
        for offset in (0..<8).reversed() { buffer.append(UInt8(truncatingIfNeeded: bits >> UInt64(offset * 8))) }
        while !buffer.isEmpty { consume(buffer[0..<64]); buffer.removeFirst(64) }
        return h.flatMap { value in (0..<4).reversed().map { UInt8(truncatingIfNeeded: value >> UInt32($0 * 8)) } }
    }
    static func digest(_ data: Data) -> [UInt8] { var s = Self(); s.update(data); return s.finish() }
    static func hex(_ bytes: [UInt8]) -> String { bytes.map { String(format: "%02x", $0) }.joined() }
}

enum VBPairing {
    static func secureRandomKey() throws -> Data {
        #if canImport(Security)
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { throw VBToolsError.invalidKey }
        return Data(bytes)
        #else
        let file = try FileHandle(forReadingFrom: URL(fileURLWithPath: "/dev/urandom"))
        defer { try? file.close() }
        let bytes = file.readData(ofLength: 32)
        guard bytes.count == 32 else { throw VBToolsError.invalidKey }
        return bytes
        #endif
    }
    static func hostKeyPath(_ vmFolder: URL) -> URL { vmFolder.appendingPathComponent(".guesttools-pairing-key") }
    static func guestKeyPath() -> URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/VolumeBoot/guesttools-pairing-key")
    }
    static func createHostKey(_ vmFolder: URL) throws -> Data {
        let path = hostKeyPath(vmFolder)
        if FileManager.default.fileExists(atPath: path.path) { return try load(path) }
        let key = try secureRandomKey()
        try store(key, to: path)
        return key
    }
    static func store(_ key: Data, to path: URL) throws {
        guard key.count == 32 else { throw VBToolsError.invalidKey }
        try FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard !FileManager.default.fileExists(atPath: path.path) else { throw VBToolsError.unsafeFile }
        guard FileManager.default.createFile(atPath: path.path, contents: key, attributes: [.posixPermissions: 0o600]) else { throw VBToolsError.unsafeFile }
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path.path)
    }
    static func load(_ url: URL) throws -> Data {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true, values.fileSize == 32 else { throw VBToolsError.invalidKey }
        let data = try Data(contentsOf: url)
        guard data.count == 32 else { throw VBToolsError.invalidKey }
        return data
    }
    static func fromHex(_ hex: String) throws -> Data {
        guard hex.count == 64, hex.allSatisfy({ $0.isHexDigit }) else { throw VBToolsError.invalidKey }
        var bytes: [UInt8] = []
        var index = hex.startIndex
        while index < hex.endIndex {
            let end = hex.index(index, offsetBy: 2)
            guard let value = UInt8(hex[index..<end], radix: 16) else { throw VBToolsError.invalidKey }
            bytes.append(value); index = end
        }
        return Data(bytes)
    }
    static func mac(key: Data, data: Data) throws -> String {
        guard key.count == 32 else { throw VBToolsError.invalidKey }
        let padded = Array(key) + Array(repeating: UInt8(0), count: 32)
        let inner = Data(padded.map { $0 ^ 0x36 }) + data
        let outer = Data(padded.map { $0 ^ 0x5c }) + Data(VBSHA256.digest(inner))
        return VBSHA256.hex(VBSHA256.digest(outer))
    }
    static func constantTimeEqual(_ a: String, _ b: String) -> Bool {
        let x = Array(a.utf8), y = Array(b.utf8)
        guard x.count == y.count else { return false }
        var mismatch: UInt8 = 0
        for i in x.indices { mismatch |= x[i] ^ y[i] }
        return mismatch == 0
    }
}

enum VBGuestAction: String, Codable { case ping, status }
private enum VBGuestTimestamp {
    static func isFresh(_ milliseconds: Int64, now: Date) -> Bool {
        let nowMilliseconds = now.timeIntervalSince1970 * 1_000
        guard nowMilliseconds.isFinite,
              nowMilliseconds > Double(Int64.min) + 120_000,
              nowMilliseconds < Double(Int64.max) - 120_000 else { return false }
        let current = Int64(nowMilliseconds)
        // Bound the untrusted timestamp before subtraction, avoiding Int64 overflow.
        return milliseconds >= current - 120_000 && milliseconds <= current + 120_000
    }
}
struct VBGuestRequest: Codable {
    let version: Int
    let id: UUID
    let milliseconds: Int64
    let action: VBGuestAction
    let authentication: String
    var canonical: Data { Data("request|\(version)|\(id.uuidString)|\(milliseconds)|\(action.rawValue)".utf8) }
    static func create(_ action: VBGuestAction, key: Data, now: Date = Date()) throws -> Self {
        let preliminary = Self(version: 2, id: UUID(), milliseconds: Int64(now.timeIntervalSince1970 * 1000), action: action, authentication: "")
        return Self(version: preliminary.version, id: preliminary.id, milliseconds: preliminary.milliseconds, action: action,
                    authentication: try VBPairing.mac(key: key, data: preliminary.canonical))
    }
    func verify(key: Data, now: Date = Date()) throws {
        guard version == 2 else { throw VBToolsError.malformedRecord }
        guard VBGuestTimestamp.isFresh(milliseconds, now: now) else { throw VBToolsError.expired }
        guard VBPairing.constantTimeEqual(authentication, try VBPairing.mac(key: key, data: canonical)) else { throw VBToolsError.unauthenticated }
    }
}
struct VBGuestReply: Codable {
    let version: Int
    let id: UUID
    let milliseconds: Int64
    let detail: String
    let authentication: String
    var canonical: Data { Data("reply|\(version)|\(id.uuidString)|\(milliseconds)|\(Data(detail.utf8).base64EncodedString())".utf8) }
    static func create(for request: VBGuestRequest, detail: String, key: Data) throws -> Self {
        let partial = Self(version: 2, id: request.id, milliseconds: Int64(Date().timeIntervalSince1970 * 1000), detail: detail, authentication: "")
        return Self(version: 2, id: partial.id, milliseconds: partial.milliseconds, detail: detail,
                    authentication: try VBPairing.mac(key: key, data: partial.canonical))
    }
    func verify(for request: VBGuestRequest, key: Data, now: Date = Date()) throws {
        guard version == 2, id == request.id, detail.utf8.count <= 4_096 else { throw VBToolsError.malformedRecord }
        guard VBGuestTimestamp.isFresh(milliseconds, now: now) else { throw VBToolsError.expired }
        guard VBPairing.constantTimeEqual(authentication, try VBPairing.mac(key: key, data: canonical)) else { throw VBToolsError.unauthenticated }
    }
}

struct VBClipboardOffer: Codable, Identifiable {
    let id: UUID
    let timestamp: Date
    let origin: String
    let text: String
}
struct VBTransferReceipt: Codable, Identifiable {
    let version: Int
    let id: UUID
    let createdAt: Date
    let origin: String
    let filename: String
    let originalName: String
    let bytes: UInt64
    let sha256: String
    let authentication: String

    var canonical: Data {
        let milliseconds = Int64(createdAt.timeIntervalSince1970 * 1_000)
        return Data("transfer|\(version)|\(id.uuidString)|\(milliseconds)|\(origin)|\(filename)|\(Data(originalName.utf8).base64EncodedString())|\(bytes)|\(sha256)".utf8)
    }

    static func create(id: UUID, createdAt: Date, origin: String, filename: String, originalName: String,
                       bytes: UInt64, sha256: String, key: Data) throws -> Self {
        let unsigned = Self(version: 2, id: id, createdAt: createdAt, origin: origin, filename: filename,
                            originalName: originalName, bytes: bytes, sha256: sha256, authentication: "")
        return Self(version: 2, id: id, createdAt: createdAt, origin: origin, filename: filename,
                    originalName: originalName, bytes: bytes, sha256: sha256,
                    authentication: try VBPairing.mac(key: key, data: unsigned.canonical))
    }

    func verify(key: Data, now: Date = Date()) throws {
        guard version == 2, origin == "host" || origin == "guest", bytes <= VBGuestToolsTransport.maxTransfer,
              originalName.utf8.count <= 1_024, sha256.count == 64, sha256.allSatisfy({ $0.isHexDigit }),
              filename == id.uuidString + VBGuestToolsTransport.safeExtension(of: filename),
              createdAt <= now.addingTimeInterval(120), createdAt >= now.addingTimeInterval(-VBGuestToolsTransport.fileRetention) else {
            throw VBToolsError.malformedRecord
        }
        guard VBPairing.constantTimeEqual(authentication, try VBPairing.mac(key: key, data: canonical)) else {
            throw VBToolsError.unauthenticated
        }
    }
}

struct VBVerifiedTransfer: Identifiable {
    let receipt: VBTransferReceipt
    let fileURL: URL
    var id: UUID { receipt.id }
}

enum VBGuestToolsTransport {
    static let maxClipboard = 65_536
    static let maxTransfer: UInt64 = 64 * 1024 * 1024
    static let chunkSize = 128 * 1024
    static let fileRetention: TimeInterval = 7 * 24 * 60 * 60
    static let clipboardRetention: TimeInterval = 10 * 60
    static let protocolRetention: TimeInterval = 10 * 60
    static let maxRetainedFilesPerDirection = 100
    static let maxRetainedFileBytesPerDirection: UInt64 = 256 * 1024 * 1024
    static let maxRetainedClipboardOffersPerDirection = 20
    static let maxRetainedClipboardBytesPerDirection: UInt64 = 1 * 1024 * 1024
    static let components = ["host-clipboard", "guest-clipboard", "requests", "replies", "host-files", "guest-files"]

    fileprivate static func safeExtension(of filename: String) -> String {
        let ext = URL(fileURLWithPath: filename).pathExtension.lowercased()
        return ext.range(of: "^[a-z0-9]{1,12}$", options: .regularExpression) == nil ? "" : "." + ext
    }

    static func prepare(root: URL) throws {
        guard isSafeDirectory(root) else { throw VBToolsError.malformedRecord }
        for name in components {
            let folder = root.appendingPathComponent(name, isDirectory: true)
            if !FileManager.default.fileExists(atPath: folder.path) {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
            }
            guard isSafeDirectory(folder) else { throw VBToolsError.malformedRecord }
            let maxFiles: Int
            let maxBytes: UInt64
            let retention: TimeInterval
            switch name {
            case "host-files", "guest-files":
                maxFiles = maxRetainedFilesPerDirection * 2; maxBytes = maxRetainedFileBytesPerDirection; retention = fileRetention
            case "host-clipboard", "guest-clipboard":
                maxFiles = maxRetainedClipboardOffersPerDirection; maxBytes = maxRetainedClipboardBytesPerDirection; retention = clipboardRetention
            default:
                maxFiles = 200; maxBytes = 2 * 1024 * 1024; retention = protocolRetention
            }
            _ = try VBGuestFileIO.withExclusiveDirectoryLock(root: root, component: name) {
                try VBGuestFileIO.prune(root: root, component: name, olderThan: Date().addingTimeInterval(-retention),
                                        maxFiles: maxFiles, maxBytes: maxBytes)
            }
        }
    }
    static func storeRecord<T: Encodable>(_ record: T, root: URL, directory: String, id: UUID) throws {
        guard components.contains(directory) else { throw VBToolsError.malformedRecord }
        let folder = root.appendingPathComponent(directory)
        guard Self.isSafeDirectory(root), Self.isSafeDirectory(folder) else { throw VBToolsError.malformedRecord }
        let clipboard = directory == "host-clipboard" || directory == "guest-clipboard"
        let retention = clipboard ? clipboardRetention : protocolRetention
        let maxFiles = clipboard ? maxRetainedClipboardOffersPerDirection : 200
        let maxBytes = clipboard ? maxRetainedClipboardBytesPerDirection : UInt64(2 * 1024 * 1024)
        let data = try JSONEncoder().encode(record)
        try VBGuestFileIO.withExclusiveDirectoryLock(root: root, component: directory) {
            let usage = try VBGuestFileIO.prune(root: root, component: directory, olderThan: Date().addingTimeInterval(-retention), maxFiles: maxFiles, maxBytes: maxBytes)
            guard usage.files < maxFiles, UInt64(data.count) <= maxBytes,
                  usage.bytes <= maxBytes - UInt64(data.count) else { throw VBToolsError.retentionQuota }
            try VBGuestFileIO.writeNewFile(data, name: id.uuidString + ".json", root: root, component: directory)
        }
    }
    private static func isSafeDirectory(_ url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
              values.isDirectory == true, values.isSymbolicLink != true else { return false }
        return true
    }
    static func records<T: Decodable>(_ type: T.Type, root: URL, directory: String, maxBytes: Int = 70_000) -> [T] {
        let folder = root.appendingPathComponent(directory, isDirectory: true)
        guard components.contains(directory), isSafeDirectory(root), isSafeDirectory(folder) else { return [] }
        let clipboard = directory == "host-clipboard" || directory == "guest-clipboard"
        _ = try? VBGuestFileIO.withExclusiveDirectoryLock(root: root, component: directory) {
            try VBGuestFileIO.prune(root: root, component: directory, olderThan: Date().addingTimeInterval(-(clipboard ? clipboardRetention : protocolRetention)),
                maxFiles: clipboard ? maxRetainedClipboardOffersPerDirection : 200,
                maxBytes: clipboard ? maxRetainedClipboardBytesPerDirection : UInt64(2 * 1024 * 1024))
        }
        guard let urls = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey]) else { return [] }
        return urls.sorted { a, b in
            let x = (try? a.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let y = (try? b.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return x > y
        }.filter { $0.pathExtension == "json" && UUID(uuidString: $0.deletingPathExtension().lastPathComponent) != nil }
            .prefix(200).compactMap { url -> T? in
                guard let p = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]),
                    p.isRegularFile == true, p.isSymbolicLink != true, (p.fileSize ?? Int.max) <= maxBytes,
                    let d = try? VBGuestFileIO.readBoundedFile(name: url.lastPathComponent, root: root, component: directory, limit: maxBytes), d.count <= maxBytes else { return nil }
                return try? JSONDecoder().decode(T.self, from: d)
            }
    }
    static func offerClipboard(_ text: String, origin: String, root: URL) throws {
        guard origin == "host" || origin == "guest" else { throw VBToolsError.invalidOrigin }
        guard !text.isEmpty && text.utf8.count <= maxClipboard else { throw VBToolsError.tooLarge }
        let offer = VBClipboardOffer(id: UUID(), timestamp: Date(), origin: origin, text: text)
        try storeRecord(offer, root: root, directory: origin + "-clipboard", id: offer.id)
    }
    static func latestClipboard(for recipient: String, root: URL) -> VBClipboardOffer? {
        guard recipient == "host" || recipient == "guest" else { return nil }
        let from = recipient == "host" ? "guest" : "host"
        return records(VBClipboardOffer.self, root: root, directory: from + "-clipboard")
            .filter { $0.origin == from && $0.text.utf8.count <= maxClipboard &&
                $0.timestamp <= Date().addingTimeInterval(60) && $0.timestamp >= Date().addingTimeInterval(-clipboardRetention) }
            .max(by: { $0.timestamp < $1.timestamp })
    }
    static func queueRequest(_ action: VBGuestAction, root: URL, key: Data) throws -> VBGuestRequest {
        let request = try VBGuestRequest.create(action, key: key)
        try storeRecord(request, root: root, directory: "requests", id: request.id)
        return request
    }
    static func verifiedReplies(root: URL, key: Data) -> [VBGuestReply] {
        var requests: [UUID: VBGuestRequest] = [:]
        for request in records(VBGuestRequest.self, root: root, directory: "requests") {
            // Reject duplicate IDs without trapping on untrusted directory contents.
            if requests[request.id] == nil { requests[request.id] = request }
        }
        return records(VBGuestReply.self, root: root, directory: "replies").filter { response in
            guard let request = requests[response.id] else { return false }
            return (try? request.verify(key: key)) != nil && (try? response.verify(for: request, key: key)) != nil
        }.sorted { $0.milliseconds > $1.milliseconds }
    }
    /// Returns number of new requests serviced. Only two fixed, non-executable actions exist.
    static func serveRequests(root: URL, key: Data, seen: inout Set<UUID>, hostname: String) -> Int {
        var processed = 0
        for request in records(VBGuestRequest.self, root: root, directory: "requests", maxBytes: 2_048) {
            guard !seen.contains(request.id), (try? request.verify(key: key)) != nil else { continue }
            seen.insert(request.id)
            let detail = request.action == .ping ? "pong" : "guest=\(hostname); agent=2"
            if let response = try? VBGuestReply.create(for: request, detail: detail, key: key),
               (try? storeRecord(response, root: root, directory: "replies", id: request.id)) != nil { processed += 1 }
        }
        return processed
    }
    /// Bounded chunked staging; partial files are removed after error, final receipt is written last.
    static func stageFile(_ source: URL, origin: String, root: URL, key: Data, progress: (Double) -> Void = { _ in }) throws -> VBTransferReceipt {
        guard origin == "host" || origin == "guest" else { throw VBToolsError.invalidOrigin }
        let properties = try source.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard properties.isRegularFile == true, properties.isSymbolicLink != true,
              let size = properties.fileSize, size >= 0, UInt64(size) <= maxTransfer else { throw VBToolsError.unsafeFile }
        let folder = root.appendingPathComponent(origin + "-files", isDirectory: true)
        var folderFlag: ObjCBool = false
        guard Self.isSafeDirectory(folder), FileManager.default.fileExists(atPath: folder.path, isDirectory: &folderFlag), folderFlag.boolValue else { throw VBToolsError.unsafeFile }
        let id = UUID()
        let ext = source.pathExtension.lowercased()
        let suffix = ext.range(of: "^[a-z0-9]{1,12}$", options: .regularExpression) == nil ? "" : "." + ext
        let name = id.uuidString + suffix
        var digest = VBSHA256()
        var written: UInt64 = 0
        var stagedReceipt: VBTransferReceipt?
        let component = origin + "-files"
        try VBGuestFileIO.withExclusiveDirectoryLock(root: root, component: component) {
            let usage = try VBGuestFileIO.prune(root: root, component: component, olderThan: Date().addingTimeInterval(-fileRetention),
                maxFiles: maxRetainedFilesPerDirection * 2, maxBytes: maxRetainedFileBytesPerDirection)
            guard usage.files + 2 <= maxRetainedFilesPerDirection * 2,
                  usage.bytes <= maxRetainedFileBytesPerDirection - UInt64(size) else { throw VBToolsError.retentionQuota }
            try VBGuestFileIO.writeStreamedFile(partialName: name + ".partial", finalName: name, root: root, component: component) { fd in
                written = try VBGuestFileIO.streamRegularFile(source, maximumBytes: maxTransfer, chunkSize: chunkSize) { chunk in
                    try VBGuestFileIO.writeAll(chunk, to: fd)
                    digest.update(chunk)
                    written += UInt64(chunk.count)
                    progress(Double(written) / Double(max(1, size)))
                }
            }
            let expectedHash = VBSHA256.hex(digest.finish())
            var storedDigest = VBSHA256()
            let storedBytes = try VBGuestFileIO.streamRegularFile(folder.appendingPathComponent(name), maximumBytes: maxTransfer,
                chunkSize: chunkSize) { storedDigest.update($0) }
            guard storedBytes == written, VBSHA256.hex(storedDigest.finish()) == expectedHash else {
                throw VBToolsError.unauthenticated
            }
            let receipt = try VBTransferReceipt.create(id: id, createdAt: Date(), origin: origin, filename: name,
                originalName: source.lastPathComponent, bytes: written, sha256: expectedHash, key: key)
            try VBGuestFileIO.writeNewFile(JSONEncoder().encode(receipt), name: id.uuidString + ".transfer.json", root: root, component: component)
            stagedReceipt = receipt
        }
        progress(1)
        guard let stagedReceipt else { throw VBToolsError.malformedRecord }
        return stagedReceipt
    }
    static func verifyFile(_ file: URL, against receipt: VBTransferReceipt) throws -> Bool {
        guard file.lastPathComponent == receipt.filename, receipt.bytes <= maxTransfer else { return false }
        var digest = VBSHA256()
        let count = try VBGuestFileIO.streamRegularFile(file, maximumBytes: maxTransfer, chunkSize: chunkSize) { digest.update($0) }
        return count == receipt.bytes && VBSHA256.hex(digest.finish()) == receipt.sha256
    }

    /// Lists only transfers whose receipt MAC and streamed payload digest both verify.
    static func verifiedTransfers(origin: String, root: URL, key: Data, now: Date = Date()) -> [VBVerifiedTransfer] {
        guard origin == "host" || origin == "guest" else { return [] }
        let component = origin + "-files"
        guard isSafeDirectory(root), isSafeDirectory(root.appendingPathComponent(component)) else { return [] }
        _ = try? VBGuestFileIO.withExclusiveDirectoryLock(root: root, component: component) {
            try VBGuestFileIO.prune(root: root, component: component, olderThan: now.addingTimeInterval(-fileRetention),
                maxFiles: maxRetainedFilesPerDirection * 2, maxBytes: maxRetainedFileBytesPerDirection)
        }
        let directory = root.appendingPathComponent(component, isDirectory: true)
        let receipts = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return receipts.filter { $0.lastPathComponent.hasSuffix(".transfer.json") }.compactMap { receiptURL in
            guard let data = try? VBGuestFileIO.readBoundedFile(name: receiptURL.lastPathComponent, root: root, component: component, limit: 8_192),
                  data.count <= 8_192, let receipt = try? JSONDecoder().decode(VBTransferReceipt.self, from: data),
                  receipt.id.uuidString + ".transfer.json" == receiptURL.lastPathComponent,
                  receipt.origin == origin, (try? receipt.verify(key: key, now: now)) != nil else { return nil }
            let file = directory.appendingPathComponent(receipt.filename)
            guard (try? verifyFile(file, against: receipt)) == true else { return nil }
            return VBVerifiedTransfer(receipt: receipt, fileURL: file)
        }.sorted { $0.receipt.createdAt > $1.receipt.createdAt }
    }

    /// Copies a previously listed transfer to a user-selected folder, rechecking
    /// the authenticated receipt and payload while streaming the destination.
    static func receiveTransfer(id: UUID, origin: String, root: URL, key: Data, destination: URL) throws -> URL {
        guard let transfer = verifiedTransfers(origin: origin, root: root, key: key).first(where: { $0.id == id }) else {
            throw VBToolsError.unauthenticated
        }
        let rawName = URL(fileURLWithPath: transfer.receipt.originalName).lastPathComponent
        let safeName = rawName.isEmpty || rawName == "." || rawName == ".." ? "received-\(id.uuidString)" : rawName
        let finalURL = destination.appendingPathComponent(safeName)
        let partialName = ".\(id.uuidString).partial"
        var digest = VBSHA256()
        var copied: UInt64 = 0
        try VBGuestFileIO.writeStreamedFile(partialName: partialName, finalName: safeName, in: destination) { fd in
            copied = try VBGuestFileIO.streamRegularFile(transfer.fileURL, maximumBytes: maxTransfer, chunkSize: chunkSize) { chunk in
                try VBGuestFileIO.writeAll(chunk, to: fd)
                digest.update(chunk)
            }
            guard copied == transfer.receipt.bytes, VBSHA256.hex(digest.finish()) == transfer.receipt.sha256 else {
                throw VBToolsError.unauthenticated
            }
        }
        return finalURL
    }
}
