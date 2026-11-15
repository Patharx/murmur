import AVFoundation
import Foundation
import MurmurCore
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
        let pieces = try chunkURLs(for: url)
        var spoken: [String] = []
        for piece in pieces {
            let text = try await recognize(url: piece)
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { spoken.append(trimmed) }
            if piece != url { try? FileManager.default.removeItem(at: piece) }
        }
        if spoken.isEmpty { throw TranscribeError.empty }
        return spoken.joined(separator: " ")
    }

    private static func recognize(url: URL) async throws -> String {
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
                box.resume(continuation, returning: result.bestTranscription.formattedString)
            }
        }
    }

    /// Silence-bounded pieces so a walk longer than a minute still transcribes on iOS 17–25.
    private static func chunkURLs(for url: URL) throws -> [URL] {
        let file = try AVAudioFile(forReading: url)
        let rate = file.processingFormat.sampleRate
        guard rate > 0, file.length > 0 else { return [url] }
        let duration = Double(file.length) / rate
        if duration <= 50 { return [url] }
        let window = AVAudioFrameCount(rate * 0.05)
        var windows: [LevelWindow] = []
        var frame: AVAudioFramePosition = 0
        while frame < file.length {
            let count = min(window, AVAudioFrameCount(file.length - frame))
            guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: count) else { break }
            file.framePosition = frame
            try file.read(into: buffer, frameCount: count)
            windows.append(LevelWindow(time: Double(frame) / rate, rms: rms(buffer)))
            frame += AVAudioFramePosition(count)
        }
        let ranges = SilenceChunker.ranges(windows: windows, duration: duration)
        if ranges.count <= 1 { return [url] }
        var urls: [URL] = []
        for (index, range) in ranges.enumerated() {
            let start = AVAudioFramePosition(range.lowerBound * rate)
            let end = min(file.length, AVAudioFramePosition(range.upperBound * rate))
            let count = AVAudioFrameCount(max(0, end - start))
            guard count > 0, let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: count) else { continue }
            file.framePosition = start
            try file.read(into: buffer, frameCount: count)
            let piece = FileManager.default.temporaryDirectory.appendingPathComponent("murmur-chunk-\(index)-\(UUID().uuidString).caf")
            let writer = try AVAudioFile(forWriting: piece, settings: file.fileFormat.settings)
            try writer.write(from: buffer)
            urls.append(piece)
        }
        return urls.isEmpty ? [url] : urls
    }

    private static func rms(_ buffer: AVAudioPCMBuffer) -> Float {
        guard let samples = buffer.floatChannelData?.pointee else { return 0 }
        let count = Int(buffer.frameLength)
        guard count > 0 else { return 0 }
        var sum: Float = 0
        for index in 0..<count {
            let sample = samples[index]
            sum += sample * sample
        }
        return sqrt(sum / Float(count))
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
