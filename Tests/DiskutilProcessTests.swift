import Foundation

@main
enum DiskutilProcessTests {
    static func main() {
        let approved = [
            ["list", "-plist"],
            ["apfs", "list", "-plist"],
            ["info", "-plist", "disk0"],
            ["info", "-plist", "disk12s3s1"],
        ]
        let rejected = [
            ["info", "-plist", "/dev/disk0"],
            ["info", "-plist", "disk0;eraseDisk"],
            ["info", "-plist", "disk0s"],
            ["eraseDisk", "-plist", "disk0"],
            ["apfs", "deleteContainer", "disk0"],
        ]
        precondition(approved.allSatisfy(DiskutilProcess.isApproved))
        precondition(rejected.allSatisfy { !DiskutilProcess.isApproved($0) })
        print("PASS: diskutil read-only command allowlist")
    }
}
