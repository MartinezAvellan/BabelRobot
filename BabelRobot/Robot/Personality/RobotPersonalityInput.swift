//
//  RobotPersonalityInput.swift
//  BabelRobot
//
//  The context the Personality Engine reasons over. It is a plain value type so
//  the engine and its classifiers stay pure and testable: given the same input
//  and config, a deterministic classifier always returns the same decision.
//

import Foundation

/// What kind of work the robot is currently helping with. Lets the engine bias
/// its reactions (e.g. stay `focused` during reasoning, `curious` for vision).
enum RobotTaskType: String, Equatable, Sendable, Codable {
    case idle
    case conversation
    case reasoning
    case screenshotUnderstanding
    case voice
    case modelLoading
    case modelUnloading
}

/// A discrete moment in the robot's life the engine should react to. These are
/// the *only* things that drive personality — never the content of the answer.
enum RobotLifecycleEvent: String, Equatable, Sendable, Codable {
    /// Nothing happened; re-evaluate ambient state (used by the idle tick).
    case tick
    /// The app/companion just appeared.
    case appeared
    /// The user submitted a prompt (text or voice).
    case userPrompted
    /// Generation began (model is working).
    case generationStarted
    /// The first streamed token arrived (the robot starts "speaking").
    case firstTokenReceived
    /// Generation finished successfully.
    case generationSucceeded
    /// Generation failed.
    case generationFailed
    /// A non-fatal heads-up worth a concerned glance.
    case warningRaised
    /// The quiet period elapsed — time to drift to sleep.
    case idleElapsed
    /// Any interaction (click, nearby cursor, key press) — wake/refresh.
    case interacted
}

/// Everything the engine needs to choose a `RobotBehaviorDecision`.
struct RobotPersonalityInput: Equatable, Sendable {

    /// What triggered this evaluation.
    var event: RobotLifecycleEvent

    /// The user's latest message, if any (used for thanks/question/excitement
    /// detection). Never used to *answer*.
    var userInput: String?

    /// The assistant's latest response, if any. Inspected only for coarse signal
    /// (e.g. it apologised / hit an error), never to generate text.
    var assistantResponse: String?

    /// The face the robot is showing right now (lets the engine avoid redundant
    /// transitions and respect ongoing sticky states).
    var currentState: RobotFaceState

    /// The kind of task in progress.
    var taskType: RobotTaskType

    init(
        event: RobotLifecycleEvent,
        userInput: String? = nil,
        assistantResponse: String? = nil,
        currentState: RobotFaceState = .idle,
        taskType: RobotTaskType = .idle
    ) {
        self.event = event
        self.userInput = userInput
        self.assistantResponse = assistantResponse
        self.currentState = currentState
        self.taskType = taskType
    }
}
