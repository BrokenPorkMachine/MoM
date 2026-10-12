import Foundation

@main enum DaemonContractTests {
    static func main() throws {
        var checks = 0
        func check(_ valid: Bool, _ message: String) {
            precondition(valid, message); checks += 1
        }
        let h = DaemonBrokerContract.health(isRoot: true)
        check(try DaemonBrokerContract.decode(DaemonBrokerContract.encode(h)) == h, "roundtrip")
        check(h.signedPeerRequired && !h.rawDiskGrantsEnabled, "physical disk grants disabled in release")
        check(h.availableOperations.contains("readOnlyTopology"), "topology diagnostic capability")
        check(DaemonBrokerContract.validWholeDisk("disk9"), "whole disk")
        for name in ["disk01", "disk3s1", "../disk3", "/dev/disk1", "disk", "disk-1", "disk1\n"] {
            check(!DaemonBrokerContract.validWholeDisk(name), "reject invalid \(name)")
        }
        check(BrokerSigningRequirements.validTeamID("ABCDEFGHIJ"), "team id")
        check(!BrokerSigningRequirements.validTeamID("abcdef0123"), "lowercase team")
        check(!BrokerSigningRequirements.validTeamID("AA\"BBBBBBB"), "injection")
        check(BrokerSigningRequirements.requirement(teamID: "ABCDEFGHIJ", bundleID: DaemonBrokerContract.mainAppBundleID) != nil, "app signing req")
        check(BrokerSigningRequirements.requirement(teamID: "ABCDEFGHIJ", bundleID: DaemonBrokerContract.machService) != nil, "daemon signing req")
        check(DaemonBrokerContract.mainAppBundleID == "ca.zensoftware.MacOnMac", "renamed app signing identity")
        check(DaemonBrokerContract.machService == "ca.zensoftware.MacOnMac.RawDiskBroker", "renamed daemon signing identity")
        check(DaemonBrokerContract.daemonPlist == "ca.zensoftware.MacOnMac.RawDiskBroker.plist", "launchd plist identity")
        check(BrokerSigningRequirements.requirement(teamID: "ABCDEFGHIJ", bundleID: "ca.zensoftware.VolumeBoot") == nil, "reject obsolete app identity")
        check(BrokerSigningRequirements.requirement(teamID: "ABCDEFGHIJ", bundleID: "attacker.bundle") == nil, "reject foreign identifier")
        let unsafe = DaemonBrokerContract.Health(protocolVersion: 3, release: DaemonBrokerContract.releaseVersion, signedPeerRequired: true,
            daemonHasRootPrivileges: true, rawDiskGrantsEnabled: true, availableOperations: ["openWritable"])
        do { _ = try DaemonBrokerContract.decode(DaemonBrokerContract.encode(unsafe)); fatalError("unsafe claims accepted") }
        catch DaemonBrokerContract.Error.unauthorizedClaim { checks += 1 }
        let incompatible = DaemonBrokerContract.Health(protocolVersion: 2, release: "0.13.0", signedPeerRequired: true,
            daemonHasRootPrivileges: true, rawDiskGrantsEnabled: false, availableOperations: ["healthReport"])
        do { _ = try DaemonBrokerContract.decode(DaemonBrokerContract.encode(incompatible)); fatalError("future protocol accepted") }
        catch DaemonBrokerContract.Error.incompatible { checks += 1 }
        check(!DaemonBrokerContract.health(isRoot: false).rawDiskGrantsEnabled, "grants disabled for unprivileged process")
        let missing = DaemonBrokerContract.Health(protocolVersion: DaemonBrokerContract.protocolVersion,
            release: DaemonBrokerContract.releaseVersion, signedPeerRequired: true, daemonHasRootPrivileges: true,
            rawDiskGrantsEnabled: false, availableOperations: ["healthReport"])
        do { _ = try DaemonBrokerContract.decode(DaemonBrokerContract.encode(missing)); fatalError("missing topology operation") }
        catch DaemonBrokerContract.Error.unauthorizedClaim { checks += 1 }
        print("Daemon contract tests PASS: \(checks) checks")
    }
}
