import Foundation

/// Tracks the sequence only. FocusCoordinator remains the timer and playback authority.
struct FocusIntervals: Codable, Equatable {
    enum Phase: String, Codable { case work, rest }
    enum State: String, Codable { case ready, active, awaitingNext, stopped }

    let workMinutes: Int
    let restMinutes: Int
    private(set) var phase: Phase = .work
    private(set) var state: State = .ready
    private(set) var completedWorkPeriods = 0

    init?(workMinutes: Int, restMinutes: Int) {
        guard (1...180).contains(workMinutes), (1...180).contains(restMinutes) else { return nil }
        self.workMinutes = workMinutes
        self.restMinutes = restMinutes
    }

    var currentMinutes: Int { phase == .work ? workMinutes : restMinutes }

    /// Called only after the user has requested and the timer has confirmed start.
    mutating func started() {
        guard state == .ready else { return }
        state = .active
    }

    /// Completion never advances or starts a new phase on its own.
    mutating func completed() {
        guard state == .active else { return }
        if phase == .work { completedWorkPeriods += 1 }
        state = .awaitingNext
    }

    /// Called in response to the user's explicit confirmation of the next phase.
    mutating func prepareNext() {
        guard state == .awaitingNext else { return }
        phase = phase == .work ? .rest : .work
        state = .ready
    }

    mutating func stop() { state = .stopped }

    var isValid: Bool {
        (1...180).contains(workMinutes) && (1...180).contains(restMinutes) && completedWorkPeriods >= 0
    }
}
