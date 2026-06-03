//
//  RobotFaceAnimator.swift
//  BabelRobot
//
//  Drives the state-dependent motion of the face with lightweight, fully
//  cancellable SwiftUI animations: blink, eye movement, breathing, loading
//  spin, and fade. Mouth/dots motion that is purely cosmetic is handled in
//  the views (gated Core Animation), so nothing here is a busy 60fps loop.
//
//  Respects Reduce Motion: when enabled, only discrete blinks remain and all
//  continuous motion (gaze drift, breathing, spin, fade) is held static.
//

import SwiftUI
import Observation

@MainActor
@Observable
final class RobotFaceAnimator {

    /// Eyes momentarily closed (blink) or shut (sleeping).
    var eyesClosed: Bool = false
    /// Normalized pupil offset, roughly -1...1 per axis.
    var gaze: CGSize = .zero
    /// Whole-head scale for the breathing effect (≈1.0).
    var breathScale: CGFloat = 1.0
    /// Rotation in degrees for the loading state.
    var spin: Double = 0
    /// Overall face opacity for the fade (unloading) effect.
    var faceOpacity: Double = 1.0

    var reduceMotion: Bool = false

    private var tasks: [Task<Void, Never>] = []
    private var currentState: RobotFaceState = .idle

    func update(for state: RobotFaceState) {
        guard state != currentState else { return }
        currentState = state
        restart(for: state)
    }

    func stop() {
        tasks.forEach { $0.cancel() }
        tasks.removeAll()
    }

    // MARK: - Loop control

    private func restart(for state: RobotFaceState) {
        stop()

        // Reset transient channels to a neutral baseline.
        withAnimation(.easeInOut(duration: 0.25)) {
            gaze = .zero
            breathScale = 1.0
            spin = 0
            faceOpacity = 1.0
            eyesClosed = (state == .sleeping)
        }

        switch state {
        case .sleeping:
            eyesClosed = true
            if !reduceMotion { startBreathing(period: 3.4, amount: 0.05) }

        case .listening:
            startBlink()
            if !reduceMotion { startBreathing(period: 2.4, amount: 0.03) }

        case .thinking, .lookingAtScreenshot:
            if !reduceMotion { startThinkingGaze() }

        case .speaking:
            break // eyes open + steady; mouth animates in the view

        case .loadingModel:
            if !reduceMotion {
                startSpin()
                startBreathing(period: 1.0, amount: 0.04) // pulse
            }

        case .unloadingModel:
            if !reduceMotion { startFade() }

        case .lookingAtCursor:
            // Blink + gentle breathing, but NO autonomous gaze: the cursor
            // tracking service writes `gaze` directly so the pupils follow
            // the pointer. Running the idle gaze loop here would fight it.
            startBlink()
            if !reduceMotion { startBreathing(period: 3.0, amount: 0.02) }

        default: // idle, happy, love, warning, error, confused
            startBlink()
            if !reduceMotion { startIdleGaze() }
        }
    }

    private func add(_ task: Task<Void, Never>) { tasks.append(task) }

    // MARK: - Animations

    private func startBlink() {
        add(Task { [weak self] in
            while !Task.isCancelled {
                let wait = Double.random(in: 3.0...5.0)
                try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
                if Task.isCancelled { return }
                await self?.blinkOnce()
            }
        })
    }

    private func blinkOnce() async {
        withAnimation(.easeInOut(duration: 0.08)) { eyesClosed = true }
        try? await Task.sleep(nanoseconds: 110_000_000)
        if Task.isCancelled { return }
        withAnimation(.easeInOut(duration: 0.10)) { eyesClosed = false }
    }

    private func startIdleGaze() {
        add(Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(Double.random(in: 2.5...4.5) * 1_000_000_000))
                if Task.isCancelled { return }
                guard let self else { return }
                withAnimation(.easeInOut(duration: 0.7)) {
                    self.gaze = CGSize(width: .random(in: -0.3...0.3), height: .random(in: -0.2...0.2))
                }
            }
        })
    }

    private func startThinkingGaze() {
        add(Task { [weak self] in
            var direction = 1.0
            while !Task.isCancelled {
                guard let self else { return }
                withAnimation(.easeInOut(duration: 0.5)) {
                    self.gaze = CGSize(width: 0.6 * direction, height: -0.1)
                }
                direction *= -1
                try? await Task.sleep(nanoseconds: 650_000_000)
            }
        })
    }

    private func startBreathing(period: Double, amount: CGFloat) {
        add(Task { [weak self] in
            var inhale = true
            while !Task.isCancelled {
                guard let self else { return }
                withAnimation(.easeInOut(duration: period / 2)) {
                    self.breathScale = inhale ? (1.0 + amount) : 1.0
                }
                inhale.toggle()
                try? await Task.sleep(nanoseconds: UInt64((period / 2) * 1_000_000_000))
            }
        })
    }

    private func startSpin() {
        add(Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                withAnimation(.linear(duration: 1.0)) { self.spin += 360 }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        })
    }

    private func startFade() {
        add(Task { [weak self] in
            var dim = true
            while !Task.isCancelled {
                guard let self else { return }
                withAnimation(.easeInOut(duration: 0.6)) {
                    self.faceOpacity = dim ? 0.4 : 1.0
                }
                dim.toggle()
                try? await Task.sleep(nanoseconds: 600_000_000)
            }
        })
    }
}
