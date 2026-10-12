import Foundation

struct VMCLIRecord: Codable {
    let id: UUID
    let path: String
    let state: VMInstallState
    let guestOS: VMGuestOS
    let diskSizeGiB: Int
}

@main
struct VMControlCLI {
    static func main() {
        do {
            let args = Array(CommandLine.arguments.dropFirst())
            guard let command = args.first else { throw CLIError.usage }
            switch command {
            case "inventory": try inventory(args)
            case "status": try status(args)
            default: throw CLIError.usage
            }
        } catch let error as CLIError {
            print("{\"error\":\"\(error.rawValue)\"}")
            exit(error.exitCode)
        } catch {
            print("{\"error\":\"operation_failed\"}")
            exit(10)
        }
    }
    private static func inventory(_ args: [String]) throws {
        guard let root = option("--root", in: args) else { throw CLIError.usage }
        let records = VMRegistry.discover(in: URL(fileURLWithPath: root)).map {
            VMCLIRecord(id: $0.record.id, path: $0.url.path, state: $0.record.state,
                        guestOS: $0.record.guestOS, diskSizeGiB: $0.record.diskSizeGiB)
        }
        try emit(records)
    }
    private static func status(_ args: [String]) throws {
        guard let path = option("--vm", in: args) else { throw CLIError.usage }
        let folder = URL(fileURLWithPath: path, isDirectory: true)
        let record = try VMRegistry.read(at: folder)
        try emit(VMCLIRecord(id: record.id, path: folder.path, state: record.state,
                             guestOS: record.guestOS, diskSizeGiB: record.diskSizeGiB))
    }
    private static func option(_ name: String, in args: [String]) -> String? {
        guard let index = args.firstIndex(of: name), args.indices.contains(index + 1) else { return nil }
        return args[index + 1]
    }
    private static func emit<T: Encodable>(_ value: T) throws {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        print(String(data: try encoder.encode(value), encoding: .utf8)!)
    }
    enum CLIError: String, Error { case usage = "invalid_arguments"; var exitCode: Int32 { 2 } }
}
