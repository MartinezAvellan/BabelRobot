//
//  VoiceHotkeyManager.swift
//  BabelRobot
//
//  Architecture for a push-to-talk hotkey (default ⌥Space). Kept DISABLED by
//  default: a true system-wide hotkey needs Accessibility permission, which is
//  out of scope for this POC. The local monitor (fires while BabelRobot is
//  frontmost) needs no permission and is the seam to build on.
//
//  Call `enable()` to start monitoring; `onTrigger` fires on key-down of the
//  configured shortcut. Global capture is stubbed behind `allowGlobal`.
//

import AppKit
import Observation

@MainActor
@Observable
final class VoiceHotkeyManager {

    struct Shortcut: Equatable, Sendable {
        var keyCode: UInt16
        var modifiers: NSEvent.ModifierFlags

        /// ⌥Space (keyCode 49 = space).
        static let optionSpace = Shortcut(keyCode: 49, modifiers: .option)

        var displayString: String {
            var s = ""
            if modifiers.contains(.control) { s += "⌃" }
            if modifiers.contains(.option)  { s += "⌥" }
            if modifiers.contains(.shift)   { s += "⇧" }
            if modifiers.contains(.command) { s += "⌘" }
            return s + (keyCode == 49 ? "Space" : "Key")
        }
    }

    var shortcut: Shortcut = .optionSpace
    var onTrigger: (() -> Void)?

    /// Opt-in: a system-wide monitor that fires even when another app is
    /// frontmost. Requires Accessibility permission — left off for the POC.
    var allowGlobal = false

    private(set) var enabled = false
    private var localMonitor: Any?
    private var globalMonitor: Any?

    func enable() {
        guard !enabled else { return }
        enabled = true

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if self.matches(event) {
                self.onTrigger?()
                return nil   // swallow the key
            }
            return event
        }

        if allowGlobal {
            globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, self.matches(event) else { return }
                self.onTrigger?()
            }
        }
    }

    func disable() {
        enabled = false
        if let m = localMonitor { NSEvent.removeMonitor(m); localMonitor = nil }
        if let m = globalMonitor { NSEvent.removeMonitor(m); globalMonitor = nil }
    }

    private func matches(_ event: NSEvent) -> Bool {
        let mods = event.modifierFlags.intersection([.command, .option, .control, .shift])
        return event.keyCode == shortcut.keyCode && mods == shortcut.modifiers
    }
}
