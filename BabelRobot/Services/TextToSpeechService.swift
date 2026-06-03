//
//  TextToSpeechService.swift
//  BabelRobot
//
//  Speaks the local LLM's response aloud with AVSpeechSynthesizer's native
//  utterance queue, so we can start talking WHILE the model is still writing:
//  the caller streams in sentences (`enqueue`) and they play back-to-back.
//
//  Configurable speech rate and voice (system default, or any installed —
//  including the softer Enhanced / Premium voices the user downloads).
//
//  The mouth "tuner" `level` is driven by `willSpeakRangeOfSpeechString`: each
//  spoken word pulses the level up and it decays between words, so the bars
//  move in sync with the speech rhythm. (Apple's speak() doesn't expose raw
//  amplitude; this is the price of native queueing + voices + rate.)
//

import AVFoundation
import Observation

@MainActor
@Observable
final class TextToSpeechService: NSObject, AVSpeechSynthesizerDelegate {

    private(set) var isSpeaking = false
    /// 0…1 level for the mouth waveform (pulses per spoken word).
    private(set) var level: Float = 0

    var volume: Float = 1.0
    var muted = false
    var languageCode: String?
    /// Specific voice identifier; nil → best voice for `languageCode`.
    var voiceIdentifier: String?
    /// AVSpeechUtterance rate (≈0.3 slow … 0.7 fast; 0.5 = default).
    var rate: Float = AVSpeechUtteranceDefaultSpeechRate

    var onStart: (() -> Void)?
    var onFinish: (() -> Void)?
    var onLevel: ((Float) -> Void)?

    private let synthesizer = AVSpeechSynthesizer()

    private var enqueuedCount = 0
    private var finishedCount = 0
    private var streamClosed = false
    private var startedOnce = false
    private var ended = false
    private var pulseDecayTask: Task<Void, Never>?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    // MARK: - Streaming API

    /// Begin a new spoken turn. Follow with `enqueue(_:)` calls and `finishStream()`.
    func startStream() {
        stopSynth()
        enqueuedCount = 0
        finishedCount = 0
        streamClosed = false
        startedOnce = false
        ended = false
        setLevel(0)
    }

    /// Queue a chunk of text (typically a sentence) to be spoken in order.
    func enqueue(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !muted, !trimmed.isEmpty else { return }
        enqueuedCount += 1
        synthesizer.speak(makeUtterance(trimmed))
    }

    /// Signal that no more text will be enqueued. Fires `onFinish` once the
    /// queue drains (or immediately if nothing was enqueued).
    func finishStream() {
        streamClosed = true
        checkDone()
    }

    /// One-shot convenience: speak a whole string.
    func speak(_ text: String) {
        startStream()
        enqueue(text)
        finishStream()
    }

    func stop() {
        stopSynth()
        finishOnce()
    }

    /// All installed voices (for the picker).
    static var availableVoices: [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices()
    }

    // MARK: - Internals

    private func makeUtterance(_ text: String) -> AVSpeechUtterance {
        let u = AVSpeechUtterance(string: text)
        u.rate = rate
        u.volume = max(0, min(1, volume))
        // No padding between queued sentences: any pre/post delay shows up as a
        // stutter when we stream sentence-by-sentence.
        u.preUtteranceDelay = 0.0
        u.postUtteranceDelay = 0.0
        if let id = voiceIdentifier, let v = AVSpeechSynthesisVoice(identifier: id) {
            u.voice = v
        } else if let code = languageCode,
                  let v = Self.bestVoice(forLanguage: code) ?? AVSpeechSynthesisVoice(language: code) {
            u.voice = v   // "System default" → best installed (Premium/Enhanced) voice
        }
        return u
    }

    /// The highest-quality installed voice for a language (Premium > Enhanced >
    /// Compact). Nil if none match.
    static func bestVoice(forLanguage language: String) -> AVSpeechSynthesisVoice? {
        let prefix = language.prefix(2).lowercased()
        return AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.lowercased().hasPrefix(prefix) }
            .max { $0.quality.rawValue < $1.quality.rawValue }
    }

    /// True when at least one Enhanced/Premium voice is installed for a language.
    static func hasNaturalVoice(forLanguage language: String) -> Bool {
        (bestVoice(forLanguage: language)?.quality.rawValue ?? 1) > AVSpeechSynthesisVoiceQuality.default.rawValue
    }

    private func stopSynth() {
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
    }

    private func checkDone() {
        guard streamClosed else { return }
        if enqueuedCount == 0 || finishedCount >= enqueuedCount {
            finishOnce()
        }
    }

    private func finishOnce() {
        guard !ended else { return }
        ended = true
        pulseDecayTask?.cancel()
        setLevel(0)
        isSpeaking = false
        onFinish?()
    }

    private func setLevel(_ value: Float) {
        level = value
        onLevel?(value)
    }

    /// Bump the level for a spoken word, then let it decay.
    private func pulse(wordLength: Int) {
        let target = min(1, 0.45 + Float(min(wordLength, 8)) * 0.07)
        setLevel(target)
        pulseDecayTask?.cancel()
        pulseDecayTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 130_000_000)
            guard let self, !Task.isCancelled, self.isSpeaking else { return }
            self.setLevel(0.15)
        }
    }

    // MARK: - AVSpeechSynthesizerDelegate (callbacks arrive off the main actor)

    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        Task { @MainActor in
            guard !self.startedOnce else { return }
            self.startedOnce = true
            self.isSpeaking = true
            self.onStart?()
        }
    }

    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer,
                                       willSpeakRangeOfSpeechString characterRange: NSRange,
                                       utterance: AVSpeechUtterance) {
        let length = characterRange.length
        Task { @MainActor in self.pulse(wordLength: length) }
    }

    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.finishedCount += 1
            self.checkDone()
        }
    }

    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.finishedCount += 1
            self.checkDone()
        }
    }
}
