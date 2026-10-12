import Foundation

final class VMControlService: NSObject, MacOnMacVMControlProtocol {
    func health(withReply reply: @escaping (String) -> Void) {
        reply(VMControlContract.encode(VMControlContract.health()))
    }

    func inventory(_ root: String, withReply reply: @escaping (String) -> Void) {
        guard safeDirectory(root) else { reply("{\"error\":\"invalid_root\"}"); return }
        struct Item: Codable { let id: UUID; let path: String; let state: VMInstallState; let guestOS: VMGuestOS }
        let items = VMRegistry.discover(in: URL(fileURLWithPath: root)).map {
            Item(id: $0.record.id, path: $0.url.path, state: $0.record.state, guestOS: $0.record.guestOS)
        }
        reply(VMControlContract.encode(items))
    }

    func status(_ folder: String, withReply reply: @escaping (String) -> Void) {
        guard safeDirectory(folder) else { reply("{\"error\":\"invalid_workspace\"}"); return }
        do {
            let record = try VMRegistry.read(at: URL(fileURLWithPath: folder, isDirectory: true))
            struct Item: Codable { let id: UUID; let path: String; let state: VMInstallState; let guestOS: VMGuestOS; let diskSizeGiB: Int }
            reply(VMControlContract.encode(Item(id: record.id, path: folder, state: record.state,
                                                 guestOS: record.guestOS, diskSizeGiB: record.diskSizeGiB)))
        } catch { reply("{\"error\":\"invalid_workspace\"}") }
    }

    private func safeDirectory(_ path: String) -> Bool {
        let url = URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL.resolvingSymlinksInPath()
        return url.path != "/" && url.path != "/dev" && !url.path.hasPrefix("/dev/") &&
            (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }
}

final class VMControlListener: NSObject, NSXPCListenerDelegate {
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        connection.exportedInterface = NSXPCInterface(with: MacOnMacVMControlProtocol.self)
        connection.exportedObject = VMControlService()
        connection.invalidationHandler = { connection.invalidationHandler = nil }
        connection.resume()
        return true
    }
}

let listener = NSXPCListener.service()
listener.delegate = VMControlListener()
listener.resume()
RunLoop.current.run()
