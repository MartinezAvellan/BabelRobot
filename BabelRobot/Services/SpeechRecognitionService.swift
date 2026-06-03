//
//  SpeechRecognitionService.swift
//  BabelRobot
//
//  Push-to-talk speech capture using Apple's Speech framework + AVAudioEngine.
//  Streams partial transcripts, prefers on-device recognition for privacy, and
//  finalizes on a short silence, an explicit stop, or a max-duration timeout.
//
//  Privacy: audio buffers are fed straight into the recognizer and are never
//  written to disk. When the locale supports on-device recognition we force it
//  so audio stays on this Mac; otherwise Apple's speech system may be used
//  (the UI surfaces a clear note about that).
//

import AVFoundation
import Speech
import Observation

@MainActor
@Observable
final class SpeechRecognitionService {

    /// Live (partial) transcript while listening.
    private(set) var transcript = ""
    private(set) var isListening = false

    /// Delivered exactly once per session when listening ends, with the final
    /// (trimmed) transcript — possibly empty if nothing was understood.
    var onFinal: ((String) -> Void)?
    /// Delivered if capture itself fails (engine/recognizer error).
    var onError: ((Error) -> Void)?

    var silenceTimeout: TimeInterval = 2.0
    var maxDuration: TimeInterval = 30.0

    private let engine = AVAudioEngine()
    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var silenceTask: Task<Void, Never>?
    private var maxTask: Task<Void, Never>?
    private var finishing = false

    /// Whether the chosen locale can recognize entirely on-device.
    func supportsOnDevice(locale: Locale) -> Bool {
        SFSpeechRecognizer(locale: locale)?.supportsOnDeviceRecognition ?? false
    }

    // MARK: - Control

    func start(locale: Locale) throws {
        // Reset the guard BEFORE cancel() so the teardown actually runs (a
        // stale `finishing == true` would skip removing the previous tap and
        // a second installTap would crash with "nullptr == Tap()").
        finishing = false
        cancel()  // ensure a clean slate

        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else {
            throw VoiceError.recognizerUnavailable
        }
        self.recognizer = recognizer

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true   // keep audio on this Mac
        }
        self.request = request

        // Tap the mic and feed buffers to the recognizer. The tap closure runs
        // on an audio thread, so it only touches locals (never main-isolated
        // state) — `append` is safe to call off-main.
        //
        // Pass `format: nil` so the engine uses the input bus's actual native
        // format. Passing a manually-read format (e.g. outputFormat) can be
        // stale and triggers "Failed to create tap due to format mismatch".
        let input = engine.inputNode
        input.removeTap(onBus: 0)   // belt-and-suspenders: never double-install
        input.installTap(onBus: 0, bufferSize: 1024, format: nil) { buffer, _ in
            // Skip empty buffers — appending one whose underlying byte size is 0
            // asserts in AVFAudio ("mDataByteSize (0) should be non-zero").
            // Check the actual byte size, not just frameLength.
            guard buffer.frameLength > 0,
                  buffer.audioBufferList.pointee.mBuffers.mDataByteSize > 0 else { return }
            request.append(buffer)
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            cancel()
            throw error
        }

        transcript = ""
        finishing = false
        isListening = true

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in self?.handle(result: result, error: error) }
        }

        // Only the max-duration cap runs up front. The short silence timer is
        // armed lazily on the FIRST detected speech, so the user has the full
        // `maxDuration` to start talking instead of being cut off by initial
        // silence right after pressing Talk.
        startMaxTimer()
    }

    /// User asked to stop (click / Stop Listening): finalize with whatever we
    /// have so far.
    func stop() {
        finish(deliver: true)
    }

    /// Abort with no callback (starting a new turn / shutting down).
    func cancel() {
        finish(deliver: false)
    }

    // MARK: - Recognition handling

    private func handle(result: SFSpeechRecognitionResult?, error: Error?) {
        guard isListening, !finishing else { return }

        if let result {
            let text = result.bestTranscription.formattedString
            transcript = text
            // Arm / refresh the trailing-silence clock only once we actually
            // have words — never before the user has spoken.
            if !text.isEmpty { resetSilenceTimer() }
            if result.isFinal {
                finish(deliver: true)
                return
            }
        }
        if let error {
            #if DEBUG
            print("[SpeechRecognition] task error: \(error.localizedDescription)")
            #endif
            let hasText = !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            if hasText {
                // A late error after we already have words isn't fatal —
                // finalize with what we have.
                finish(deliver: true)
            } else {
                // Failed before any speech: surface the real reason (e.g.
                // Dictation disabled) instead of a misleading "couldn't
                // understand".
                finish(deliver: false, error: Self.mapError(error))
            }
        }
    }

    /// Translate an opaque recognizer error into a friendly, actionable one.
    private static func mapError(_ error: Error) -> Error {
        let text = error.localizedDescription.lowercased()
        if text.contains("dictation") || text.contains("siri") {
            return VoiceError.dictationDisabled
        }
        return VoiceError.recognizerUnavailable
    }

    // MARK: - Timers

    // MainActor-isolated Tasks (not Timer): the class is @MainActor, so these
    // closures inherit its isolation and capturing `self` is safe — unlike a
    // Timer's @Sendable block, which Swift 6 rejects.

    private func resetSilenceTimer() {
        silenceTask?.cancel()
        let timeout = silenceTimeout
        silenceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.stop()
        }
    }

    private func startMaxTimer() {
        maxTask?.cancel()
        let limit = maxDuration
        maxTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(limit * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.stop()
        }
    }

    // MARK: - Teardown

    private func finish(deliver: Bool, error: Error? = nil) {
        guard !finishing else { return }
        finishing = true

        silenceTask?.cancel(); silenceTask = nil
        maxTask?.cancel(); maxTask = nil

        if engine.isRunning { engine.stop() }
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        task = nil
        request = nil

        let wasListening = isListening
        isListening = false

        if let error {
            onError?(error)
            return
        }
        if deliver, wasListening {
            let final = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            onFinal?(final)
        }
    }
}
