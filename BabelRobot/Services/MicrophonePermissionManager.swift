//
//  MicrophonePermissionManager.swift
//  BabelRobot
//
//  Centralizes the two authorizations a voice turn needs: microphone capture
//  (AVCaptureDevice) and speech recognition (SFSpeechRecognizer). Both are
//  requested lazily, only when the user first tries to talk.
//

import AVFoundation
import Speech
import Observation

@MainActor
@Observable
final class MicrophonePermissionManager {

    enum Status: Equatable, Sendable {
        case notDetermined, granted, denied
    }

    private(set) var microphone: Status = .notDetermined
    private(set) var speech: Status = .notDetermined

    init() {
        refresh()
    }

    /// Re-read the current OS authorization status (does not prompt).
    func refresh() {
        microphone = Self.map(AVCaptureDevice.authorizationStatus(for: .audio))
        speech = Self.mapSpeech(SFSpeechRecognizer.authorizationStatus())
    }

    /// Request both permissions in turn. Returns true only if BOTH are granted.
    /// Throws a friendly message on the first denial.
    func requestAll() async throws {
        // Microphone first.
        if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
            _ = await AVCaptureDevice.requestAccess(for: .audio)
        }
        microphone = Self.map(AVCaptureDevice.authorizationStatus(for: .audio))
        guard microphone == .granted else {
            throw VoiceError.microphoneDenied
        }

        // Then speech recognition.
        if SFSpeechRecognizer.authorizationStatus() == .notDetermined {
            await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { _ in continuation.resume() }
            }
        }
        speech = Self.mapSpeech(SFSpeechRecognizer.authorizationStatus())
        guard speech == .granted else {
            throw VoiceError.speechDenied
        }
    }

    var bothGranted: Bool { microphone == .granted && speech == .granted }

    // MARK: - Mapping

    private static func map(_ status: AVAuthorizationStatus) -> Status {
        switch status {
        case .authorized:            return .granted
        case .denied, .restricted:   return .denied
        case .notDetermined:         return .notDetermined
        @unknown default:            return .denied
        }
    }

    private static func mapSpeech(_ status: SFSpeechRecognizerAuthorizationStatus) -> Status {
        switch status {
        case .authorized:            return .granted
        case .denied, .restricted:   return .denied
        case .notDetermined:         return .notDetermined
        @unknown default:            return .denied
        }
    }
}

/// Friendly, user-facing voice errors.
enum VoiceError: LocalizedError {
    case microphoneDenied
    case speechDenied
    case dictationDisabled
    case recognizerUnavailable
    case noSpeechDetected
    case noModelLoaded
    case generationFailed

    var errorDescription: String? {
        switch self {
        case .microphoneDenied:     return "Microphone access is required."
        case .speechDenied:         return "Speech recognition access is required."
        case .dictationDisabled:    return "Turn on Dictation in System Settings ▸ Keyboard ▸ Dictation to use voice."
        case .recognizerUnavailable: return "Speech recognition isn't available right now."
        case .noSpeechDetected:     return "I could not understand that."
        case .noModelLoaded:        return "Please load a model first."
        case .generationFailed:     return "Local generation failed. Please try again."
        }
    }
}
