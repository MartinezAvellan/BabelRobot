//
//  CursorTrackingService.swift
//  BabelRobot
//
//  Polls the pointer location and turns it into a smoothed, range-limited
//  gaze offset + head tilt so the companion's pupils and head lean toward the
//  cursor — without ever moving the whole robot.
//
//  Performance: a single timer (added to the common run-loop modes so it keeps
//  firing during scroll/drag). The owner sets the cadence — fast while awake &
//  following, slow while asleep (proximity-only) — and stops it entirely when
//  the companion is hidden. No 60fps loop; default is 30fps when active.
//
//  `NSEvent.mouseLocation` needs no special permission and is read on the main
//  thread, where this whole service lives.
//

import AppKit
import Observation

@MainActor
@Observable
final class CursorTrackingService {

    /// Smoothed pupil offset, roughly -1...1 per axis (SwiftUI coordinates:
    /// +width = right, +height = down).
    private(set) var gaze: CGSize = .zero
    /// Smoothed head tilt in degrees (small range), + = toward the right.
    private(set) var headTilt: Double = 0

    /// Center of the companion window in screen coordinates (bottom-left
    /// origin), kept up to date by the owner as the window moves.
    var companionCenter: CGPoint = .zero

    /// When false, the gaze/tilt relax to neutral but the timer still ticks
    /// (so proximity/sleep checks keep running). Set false for Reduce Motion,
    /// follow-cursor off, or while asleep.
    var active = true

    /// Invoked every tick with the raw pointer location (screen coords).
    var onTick: ((CGPoint) -> Void)?

    /// Distance (pt) at which the gaze reaches full deflection.
    private let gazeReference: CGFloat = 420
    private let maxTilt: Double = 8
    private let smoothing: CGFloat = 0.22

    private var timer: Timer?
    private var cadence: TimeInterval = 1.0 / 30.0

    // MARK: - Lifecycle

    func start(cadence: TimeInterval) {
        self.cadence = cadence
        schedule()
    }

    /// Change tick frequency (e.g. awake↔asleep) without dropping the loop.
    func setCadence(_ cadence: TimeInterval) {
        guard timer != nil, cadence != self.cadence else { return }
        self.cadence = cadence
        schedule()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        gaze = .zero
        headTilt = 0
    }

    private func schedule() {
        timer?.invalidate()
        let t = Timer(timeInterval: cadence, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    // MARK: - Tick

    private func tick() {
        let mouse = NSEvent.mouseLocation

        let target: CGSize
        let tiltTarget: Double
        if active {
            let dx = mouse.x - companionCenter.x
            let dy = mouse.y - companionCenter.y
            let nx = clamp(dx / gazeReference)
            // Screen y is bottom-up; SwiftUI +height is down, so invert.
            let ny = clamp(-dy / gazeReference)
            target = CGSize(width: nx, height: ny)
            tiltTarget = Double(clamp(dx / (gazeReference * 1.4))) * maxTilt
        } else {
            target = .zero
            tiltTarget = 0
        }

        // Manual lerp = smooth interpolation, no Core Animation churn.
        gaze = CGSize(
            width: gaze.width + (target.width - gaze.width) * smoothing,
            height: gaze.height + (target.height - gaze.height) * smoothing)
        headTilt += (tiltTarget - headTilt) * Double(smoothing)

        onTick?(mouse)
    }

    private func clamp(_ v: CGFloat, to limit: CGFloat = 0.9) -> CGFloat {
        max(-limit, min(limit, v))
    }
}
