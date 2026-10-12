import Foundation

@main
struct WorkspaceLeaseProcess {
    static func main() throws {
        let arguments = CommandLine.arguments
        guard arguments.count == 3 else { exit(2) }
        let folder = URL(fileURLWithPath: arguments[2], isDirectory: true)
        if arguments[1] == "hold" {
            let lease = try VMWorkspaceLease(folder: folder)
            try Data("held".utf8).write(to: folder.appendingPathComponent("lease-held"), options: .atomic)
            Thread.sleep(forTimeInterval: 2.0)
            withExtendedLifetime(lease) {}
            exit(0)
        } else if arguments[1] == "probe-held" {
            do {
                _ = try VMWorkspaceLease(folder: folder)
                exit(1)
            } catch VMWorkspaceLeaseError.inUse {
                exit(0)
            }
        } else if arguments[1] == "probe" {
            let lease = try VMWorkspaceLease(folder: folder)
            withExtendedLifetime(lease) {}
            exit(0)
        } else {
            exit(2)
        }
    }
}
