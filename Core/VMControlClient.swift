import Foundation
import ServiceManagement

@MainActor
final class VMControlClient {
    enum Failure: LocalizedError { case unavailable, malformed, timeout
        var errorDescription: String? {
            switch self { case .unavailable: return "VM control service is unavailable or not registered"; case .malformed: return "VM control service returned malformed data"; case .timeout: return "VM control service timed out" }
        }
    }

    private var service: SMAppService { .agent(plistName: VMControlContract.daemonPlist) }
    func status() -> String {
        switch service.status { case .enabled: return "Enabled"; case .requiresApproval: return "Requires approval"; case .notRegistered: return "Not registered"; case .notFound: return "Not found"; @unknown default: return "Unknown" }
    }
    func register() throws -> String { try service.register(); return status() }
    func unregister() throws -> String { try service.unregister(); return status() }

    func health() async throws -> VMControlContract.Health {
        let response = try await request { connection, reply in
            (connection.remoteObjectProxyWithErrorHandler { _ in reply(nil) } as? MacOnMacVMControlProtocol)?.health { reply($0) }
        }
        guard let data = response.data(using: .utf8), let health = try? JSONDecoder().decode(VMControlContract.Health.self, from: data), health.protocolVersion == VMControlContract.protocolVersion else { throw Failure.malformed }
        return health
    }

    private func request(_ send: @escaping (NSXPCConnection, @escaping (String?) -> Void) -> Void) async throws -> String {
        let connection = NSXPCConnection(machServiceName: VMControlContract.machService, options: [])
        connection.remoteObjectInterface = NSXPCInterface(with: MacOnMacVMControlProtocol.self)
        connection.resume(); defer { connection.invalidate() }
        return try await withCheckedThrowingContinuation { continuation in
            let finished = NSLock(); var complete = false
            func finish(_ result: Result<String, Error>) { finished.lock(); defer { finished.unlock() }; guard !complete else { return }; complete = true; continuation.resume(with: result) }
            send(connection) { value in
                if let value { finish(.success(value)) } else { finish(.failure(Failure.unavailable)) }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { finish(.failure(Failure.timeout)) }
        }
    }
}
