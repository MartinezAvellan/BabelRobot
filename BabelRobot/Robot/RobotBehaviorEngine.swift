//
//  RobotBehaviorEngine.swift
//  BabelRobot
//
//  Owns the companion's "ambient" behavior when no AI emotion is active:
//  staying awake while there's interaction, drifting to sleep after a quiet
//  period, and waking again. It does not run its own timer — the companion's
//  single cursor tick calls `evaluate(now:)` so the whole feature uses one
//  low-frequency loop.
//

import Foundation
import Observation

@MainActor
@Observable
final class RobotBehaviorEngine {

    /// Seconds of no interaction before the robot falls asleep.
    static let sleepDelay: TimeInterval = 5 * 60

    private(set) var isAsleep = false

    /// User preferences (mirrored from the companion settings).
    var sleepWhenIdle = true
    var followCursor = true

    /// Fired when the derived behavior changes (asleep ⇄ awake).
    var onChange: (() -> Void)?

    private var lastInteraction = Date()

    /// The face to show when no emotion overrides it.
    var baseState: RobotFaceState {
        if isAsleep { return .sleeping }
        return followCursor ? .lookingAtCursor : .idle
    }

    /// Record any interaction (prompt, click, nearby cursor) and wake up.
    func noteInteraction(now: Date = Date()) {
        lastInteraction = now
        if isAsleep { setAsleep(false) }
    }

    /// Called every tick. Transitions to sleep once the quiet period elapses.
    /// `blocked` is true while an AI emotion is active (don't sleep mid-task).
    func evaluate(now: Date = Date(), blocked: Bool) {
        guard sleepWhenIdle, !isAsleep, !blocked else { return }
        if now.timeIntervalSince(lastInteraction) >= Self.sleepDelay {
            setAsleep(true)
        }
    }

    func reset() {
        lastInteraction = Date()
        if isAsleep { setAsleep(false) }
    }

    private func setAsleep(_ value: Bool) {
        guard value != isAsleep else { return }
        isAsleep = value
        onChange?()
    }
}
