import Foundation
@main struct BrokerContractTests {
    static func main() throws {
        var checks = 0
        func check(_ condition: Bool, _ name: String) {
            checks += 1
            precondition(condition, name)
        }
        let report = BrokerProtocolContract.report()
        let decoded = try BrokerProtocolContract.decode(BrokerProtocolContract.encode(report))
        check(decoded == report, "roundtrip")
        check(decoded.protocolVersion == 1, "version")
        check(!decoded.privileged && !decoded.rawDiskAccessEnabled, "never pretend privileged")
        check(!decoded.capabilities.contains(.physicalDiskRead), "no raw read")
        check(!decoded.capabilities.contains(.physicalDiskWrite), "no raw write")
        let incompatible = BrokerProtocolContract.Report(protocolVersion: 2, serviceVersion: "x", capabilities: [], privileged: false, rawDiskAccessEnabled: false)
        do { _ = try BrokerProtocolContract.decode(BrokerProtocolContract.encode(incompatible)); preconditionFailure("version must fail") }
        catch BrokerProtocolContract.ContractError.incompatibleVersion { checks += 1 }
        let unsafe = BrokerProtocolContract.Report(protocolVersion: 1, serviceVersion: "x", capabilities: [.physicalDiskRead], privileged: false, rawDiskAccessEnabled: false)
        do { _ = try BrokerProtocolContract.decode(BrokerProtocolContract.encode(unsafe)); preconditionFailure("unsafe must fail") }
        catch BrokerProtocolContract.ContractError.unsafeClaim { checks += 1 }
        do { _ = try BrokerProtocolContract.decode(String(repeating: "x", count: 4097)); preconditionFailure("oversized must fail") }
        catch BrokerProtocolContract.ContractError.invalidPayload { checks += 1 }
        print("PASS: \(checks) broker protocol checks")
    }
}
