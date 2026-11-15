import AVFoundation
import Foundation
import Speech

enum TranscribeError: Error {
    case notAuthorized
    case unavailable
    case empty
}

/// The file is the authority. The live line is only a confidence display.
enum FileTranscriber {
    static func transcribe(url: URL) async throws -> String {
        if #available(iOS 26.0, *) {
            if let modern = try? await SpeechAnalyzerTranscriber.transcribe(url: url) {
                let trimmed = modern.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return modern }
            }
        }
        return try await LegacyFileTranscriber.transcribe(url: url)
    }
}

@available(iOS 26.0, *)
enum SpeechAnalyzerTranscriber {
    static func transcribe(url: URL) async throws -> String {
        let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale.current) ?? Locale.current
        let transcriber = SpeechTranscriber(locale: locale, preset: .transcription)
        if let installer = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await installer.downloadAndInstall()
        }
        let collecting = Task { () -> String in
            var text = ""
            for try await result in transcriber.results {
                text += String(result.text.characters)
            }
            return text
        }
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let file = try AVAudioFile(forReading: url)
        if let last = try await analyzer.analyzeSequence(from: file) {
            try await analyzer.finalizeAndFinish(through: last)
        } else {
            await analyzer.cancelAndFinishNow()
        }
        return try await collecting.value
    }
}

enum LegacyFileTranscriber {
    static func transcribe(url: URL) async throws -> String {
        let status = await authorization()
        guard status == .authorized else { throw TranscribeError.notAuthorized }
        guard let recognizer = SFSpeechRecognizer(), recognizer.isAvailable else {
            throw TranscribeError.unavailable
        }
        let request = SFSpeechURLRecognitionRequest(url: url)
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true
        return try await withCheckedThrowingContinuation { continuation in
            let box = ResumeBox()
            recognizer.recognitionTask(with: request) { result, error in
                if let error {
                    box.resume(continuation, throwing: error)
                    return
                }
                guard let result, result.isFinal else { return }
                let text = result.bestTranscription.formattedString
                if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    box.resume(continuation, throwing: TranscribeError.empty)
                } else {
                    box.resume(continuation, returning: text)
                }
            }
        }
    }

    static func authorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }
}

/// SFSpeechRecognizer can call its handler more than once. Only the first resume counts.
private final class ResumeBox: @unchecked Sendable {
    private var resumed = false
    private let lock = NSLock()

    func resume(_ continuation: CheckedContinuation<String, Error>, returning value: String) {
        lock.lock()
        defer { lock.unlock() }
        guard !resumed else { return }
        resumed = true
        continuation.resume(returning: value)
    }

    func resume(_ continuation: CheckedContinuation<String, Error>, throwing error: Error) {
        lock.lock()
        defer { lock.unlock() }
        guard !resumed else { return }
        resumed = true
        continuation.resume(throwing: error)
    }
}
