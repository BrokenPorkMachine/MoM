import Foundation

/// Tracks reservations in memory; does not elevate privilege or grant handles.
/// A future privileged service must own authoritative leases, keyed by physical identity.
struct DiskLeaseStateMachine {
    enum State: Equatable { case idle, reserved(UUID), attached(UUID), failed }
    enum TransitionError: Error { case conflictingLease, invalidTransition }
    private(set) var state: State = .idle

    mutating func reserve(_ session: UUID) throws {
        guard state == .idle else { throw TransitionError.conflictingLease }
        state = .reserved(session)
    }
    mutating func attach(_ session: UUID) throws {
        guard state == .reserved(session) else { throw TransitionError.invalidTransition }
        state = .attached(session)
    }
    mutating func release(_ session: UUID) throws {
        guard state == .reserved(session) || state == .attached(session) else {
            throw TransitionError.invalidTransition
        }
        state = .idle
    }
    mutating func failClosed() { state = .failed }
    mutating func resetAfterRevalidation() throws {
        guard state == .failed else { throw TransitionError.invalidTransition }
        state = .idle
    }
}
