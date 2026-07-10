public struct PomodoroCompletionNotificationGate {
    private var previousSnapshot: PomodoroSnapshot?

    public init() {}

    public mutating func observe(_ snapshot: PomodoroSnapshot) -> PomodoroMode? {
        guard let previousSnapshot else {
            self.previousSnapshot = snapshot
            return nil
        }
        self.previousSnapshot = snapshot
        let wasActive = previousSnapshot.status == .running || previousSnapshot.status == .paused
        if previousSnapshot.mode == snapshot.mode,
           wasActive,
           snapshot.status == .completed {
            return snapshot.mode
        }
        return nil
    }
}
