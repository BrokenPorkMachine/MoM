import Foundation

/// Versioned diagnostics contract. This protocol never authorizes physical media access.
enum BrokerProtocolContract {
    static let version = 1
    static let maximumBSDNameBytes = 32
    static let maximumResponseBytes = 4096
    static let requestTimeoutNanoseconds: UInt64 = 8_000_000_000

    enum Capability: String, Codable { case diagnostics, advisoryPreflight, physicalDiskRead, physicalDiskWrite }
    struct Report: Codable, Equatable {
        let protocolVersion: Int
        let serviceVersion: String
        let capabilities: [Capability]
        let privileged: Bool
        let rawDiskAccessEnabled: Bool
    }
    static func report() -> Report {
        Report(protocolVersion: version, serviceVersion: "0.12.0",
               capabilities: [.diagnostics, .advisoryPreflight], privileged: false,
               rawDiskAccessEnabled: false)
    }
    static func encode(_ report: Report) -> String {
        guard let data = try? JSONEncoder().encode(report),
              data.count <= maximumResponseBytes,
              let value = String(data: data, encoding: .utf8) else { return "{}" }
        return value
    }
    static func decode(_ payload: String) throws -> Report {
        guard payload.utf8.count <= maximumResponseBytes,
              let data = payload.data(using: .utf8) else { throw ContractError.invalidPayload }
        let report = try JSONDecoder().decode(Report.self, from: data)
        guard report.protocolVersion == version else { throw ContractError.incompatibleVersion }
        guard !report.privileged && !report.rawDiskAccessEnabled &&
                !report.capabilities.contains(.physicalDiskRead) &&
                !report.capabilities.contains(.physicalDiskWrite) else { throw ContractError.unsafeClaim }
        return report
    }
    enum ContractError: Error { case invalidPayload, incompatibleVersion, unsafeClaim }
}
