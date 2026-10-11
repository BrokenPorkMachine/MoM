import Foundation

/// Runs independent work with bounded concurrency while dispatching higher
/// priority items first. Results retain the caller's input order.
enum TaskDispatchQueue {
    static func map<Input: Sendable, Output: Sendable>(
        _ inputs: [Input],
        maxConcurrent: Int,
        priority: @Sendable (Input) -> Int = { _ in 0 },
        resourceKey: @Sendable (Input) -> String? = { _ in nil },
        operation: @escaping @Sendable (Input) async throws -> Output
    ) async throws -> [Output] {
        guard !inputs.isEmpty else { return [] }
        let workerLimit = max(1, maxConcurrent)
        let dispatchOrder = inputs.indices.sorted {
            let lhs = priority(inputs[$0])
            let rhs = priority(inputs[$1])
            return lhs == rhs ? $0 < $1 : lhs < rhs
        }

        return try await withThrowingTaskGroup(of: (Int, String?, Output).self) { group in
            var pending = dispatchOrder
            var activeResources = Set<String>()
            var running = 0
            var results = Array<Output?>(repeating: nil, count: inputs.count)
            func launchAvailable() {
                while running < workerLimit {
                    guard let position = pending.firstIndex(where: { index in
                        guard let key = resourceKey(inputs[index]) else { return true }
                        return !activeResources.contains(key)
                    }) else { return }
                    let index = pending.remove(at: position)
                    let key = resourceKey(inputs[index])
                    if let key { activeResources.insert(key) }
                    running += 1
                    group.addTask { (index, key, try await operation(inputs[index])) }
                }
            }

            launchAvailable()
            while let (index, key, value) = try await group.next() {
                running -= 1
                if let key { activeResources.remove(key) }
                results[index] = value
                launchAvailable()
            }
            return results.map { $0! }
        }
    }
}
