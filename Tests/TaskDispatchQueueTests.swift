import Foundation

actor DispatchProbe {
    private(set) var starts: [Int] = []
    private(set) var active = 0
    private(set) var peak = 0
    private var activeKeys = Set<String>()
    private(set) var overlappingKeys = false

    func begin(_ value: Int) {
        starts.append(value)
        active += 1
        peak = max(peak, active)
    }

    func finish() { active -= 1 }

    func begin(_ value: Int, key: String) {
        if !activeKeys.insert(key).inserted { overlappingKeys = true }
        begin(value)
    }

    func finish(key: String) {
        activeKeys.remove(key)
        finish()
    }
}

@main
enum TaskDispatchQueueTests {
    static func main() async throws {
        let priorityProbe = DispatchProbe()
        let ordered = try await TaskDispatchQueue.map([0, 1, 2, 3], maxConcurrent: 1,
            priority: { $0 == 3 ? 0 : 1 }) { value in
            await priorityProbe.begin(value)
            await priorityProbe.finish()
            return value * 10
        }
        let startOrder = await priorityProbe.starts
        guard startOrder == [3, 0, 1, 2], ordered == [0, 10, 20, 30] else {
            fatalError("priority dispatch or input-order result contract failed: \(startOrder), \(ordered)")
        }

        let concurrencyProbe = DispatchProbe()
        let concurrent = try await TaskDispatchQueue.map(Array(0..<12), maxConcurrent: 3) { value in
            await concurrencyProbe.begin(value)
            try await Task.sleep(nanoseconds: 2_000_000)
            await concurrencyProbe.finish()
            return value
        }
        let peak = await concurrencyProbe.peak
        guard concurrent == Array(0..<12), peak == 3 else {
            fatalError("worker bound or result ordering failed: peak=\(peak)")
        }

        let resourceProbe = DispatchProbe()
        let resourceJobs = Array(0..<8)
        _ = try await TaskDispatchQueue.map(resourceJobs, maxConcurrent: 4,
            resourceKey: { $0 < 6 ? "vm-A" : "vm-B" }) { value in
            let key = value < 6 ? "vm-A" : "vm-B"
            await resourceProbe.begin(value, key: key)
            try await Task.sleep(nanoseconds: 2_000_000)
            await resourceProbe.finish(key: key)
            return value
        }
        guard !(await resourceProbe.overlappingKeys) else {
            fatalError("jobs sharing a resource key overlapped")
        }

        do {
            _ = try await TaskDispatchQueue.map([0, 1, 2], maxConcurrent: 2) { value in
                if value == 1 { throw NSError(domain: "TaskDispatchQueueTests", code: 1) }
                return value
            }
            fatalError("work errors must propagate")
        } catch let error as NSError where error.domain == "TaskDispatchQueueTests" && error.code == 1 {
            print("PASS: priority ordering, bounded concurrency, resource serialization, stable results, and error propagation")
        }
    }
}
