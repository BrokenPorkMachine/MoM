import Foundation
@main struct BrokerAuthorizationTests {
    static func main() {
        var assertions = 0
        func check(_ pass: Bool, _ name: String) {
            assertions += 1
            if !pass { fatalError("FAILED: \(name)") }
        }
        let good = ["disk0", "disk1", "disk42", "disk9999999999"]
        let bad = ["", "disk", "disk01", "disk3s1", "/dev/rdisk3", "../../disk2", "disk-1", "disk0\n", "disk99999999999", "disk1;ls", "DISK2"]
        for name in good { check(BrokerAuthorizationPolicy.isValidBSDName(name), "valid \(name)") }
        for name in bad { check(!BrokerAuthorizationPolicy.isValidBSDName(name), "reject \(name)") }
        check(BrokerAuthorizationPolicy.decide(.capability) == .allowDiagnostic, "capability")
        check(BrokerAuthorizationPolicy.decide(.leaseStatus) == .allowDiagnostic, "lease status")
        check(BrokerAuthorizationPolicy.decide(.preflight, bsdName: "disk3") == .allowDiagnostic, "preflight")
        check(BrokerAuthorizationPolicy.decide(.preflight, bsdName: "disk3s2") != .allowDiagnostic, "partition denied")
        for op in [BrokerAuthorizationPolicy.Operation.openReadOnly, .openWritable] {
            check(BrokerAuthorizationPolicy.decide(op, bsdName: "disk3") != .allowDiagnostic, "never grant disk handle")
        }
        print("PASS: \(assertions) broker authorization assertions")
    }
}
