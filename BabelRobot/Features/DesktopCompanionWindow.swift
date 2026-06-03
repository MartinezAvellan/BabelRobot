//
//  DesktopCompanionWindow.swift
//  BabelRobot
//
//  The floating, borderless, transparent panel that hosts the desktop
//  companion. It is a non-activating panel so clicking/dragging the robot
//  never steals focus from whatever app the user is working in, yet it still
//  receives mouse events (click-through is OFF by default).
//
//  Draggable anywhere by the background; floats above normal windows; joins
//  all Spaces so it stays visible as the user switches desktops.
//

import AppKit

final class DesktopCompanionWindow: NSPanel {

    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false)

        isFloatingPanel = true
        level = .floating
        hidesOnDeactivate = false
        isReleasedWhenClosed = false          // survives main-window close

        // Transparent: the robot draws its own rounded head.
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false                      // SwiftUI renders the soft shadow

        // Draggable by the background; click-through disabled by default.
        isMovableByWindowBackground = true
        ignoresMouseEvents = false

        // Stay visible across Spaces and full-screen apps.
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        animationBehavior = .utilityWindow
    }

    // A borderless panel must opt in to receive key/clicks; main stays false so
    // the app behind it keeps its active state.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// Toggle whether the panel floats above everything or sits at normal level.
    func setAlwaysOnTop(_ onTop: Bool) {
        level = onTop ? .floating : .normal
    }
}
