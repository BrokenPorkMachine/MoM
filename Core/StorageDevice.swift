import Foundation

struct StorageDevice: Identifiable, Codable, Hashable, Sendable {
    var id: String { identifier }
    let identifier: String
    let name: String
    let filesystem: String
    let mountPoint: String
    let transport: String
    let isWholeDisk: Bool
    let isInternal: Bool
    let isWritable: Bool
    let sizeBytes: UInt64
}
