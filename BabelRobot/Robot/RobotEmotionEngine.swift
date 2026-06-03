//
//  RobotEmotionEngine.swift
//  BabelRobot
//
//  Translates AI / LLM lifecycle events into the companion's emotional face
//  state. Two kinds of emotions:
//
//   • Sticky    — hold until the next event (thinking, speaking).
//   • Timed     — auto-clear after a fixed duration (happy 2s, confused 3s).
//
//  When no emotion is active, `activeState` is nil and the behavior engine
//  decides the face (idle / lookingAtCursor / sleeping).
//

import SwiftUI
import Observation

@MainActor
@Observable
final class RobotEmotionEngine {

    /// The current emotion, or nil when the robot is emotionally "neutral".
    private(set) var activeState: RobotFaceState?

    /// Fired whenever `activeState` changes, so the owner can re-sync the face.
    var onChange: (() -> Void)?

    private var clearTask: Task<Void, Never>?
    private var isSticky = false

    // MARK: - Event hooks (called from the AI bridge)

    /// User submitted a prompt / generation is starting.
    func prompted() { set(.thinking, sticky: true) }

    /// First token arrived / streaming a response.
    func speaking() { set(.speaking, sticky: true) }

    /// Generation finished successfully.
    func generationSucceeded() { set(.happy, for: 2.0) }

    /// Generation failed — show a friendly confused face.
    func generationFailed() { set(.confused, for: 3.0) }

    /// A non-fatal heads-up.
    func warn() { set(.warning, for: 2.0) }

    /// Release a sticky emotion (thinking/speaking) when the AI goes idle.
    /// Timed emotions (happy/confused) are left alone so they run their course.
    func releaseSticky() {
        guard isSticky else { return }
        clear()
    }

    /// Forcefully drop any emotion (e.g. companion disabled).
    func reset() { clear() }

    // MARK: - Internals

    private func set(_ state: RobotFaceState, sticky: Bool) {
        clearTask?.cancel()
        clearTask = nil
        isSticky = sticky
        update(state)
    }

    private func set(_ state: RobotFaceState, for duration: TimeInterval) {
        clearTask?.cancel()
        isSticky = false
        update(state)
        clearTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            if Task.isCancelled { return }
            self?.clear()
        }
    }

    private func clear() {
        clearTask?.cancel()
        clearTask = nil
        isSticky = false
        update(nil)
    }

    private func update(_ state: RobotFaceState?) {
        guard state != activeState else { return }
        activeState = state
        onChange?()
    }
}
