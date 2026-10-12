import Foundation

#if canImport(ObjectiveC)
@objc protocol MacOnMacVMControlProtocol {
    func health(withReply reply: @escaping (String) -> Void)
    func inventory(_ root: String, withReply reply: @escaping (String) -> Void)
    func status(_ folder: String, withReply reply: @escaping (String) -> Void)
}
#endif

enum VMControlContract {
    static let protocolVersion = 1
    static let machService = "ca.zensoftware.MacOnMac.VMControl"
    static let daemonExecutable = "MacOnMacVMControl"
    static let daemonPlist = machService + ".plist"
    static let maxPayloadBytes = 64 * 1024

    struct Health: Codable { let protocolVersion: Int; let release: String; let operations: [String] }
    static func health() -> Health {
        Health(protocolVersion: protocolVersion, release: "0.16.0", operations: ["health", "inventory", "status"])
    }
    static func encode<T: Encodable>(_ value: T) -> String {
        guard let data = try? JSONEncoder().encode(value), data.count <= maxPayloadBytes else { return "{}" }
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}
