import AVFoundation
import AudioToolbox
import Foundation
import MurmurCore
import Speech

/// Listens into a 32 kbps mono AAC file and a live confidence line.
///
/// AVAudioRecorder cannot share the microphone with a recogniser, and the
/// recording screen has to show words while the level moves. One engine tap
/// writes the AAC file and feeds the recogniser. The file is transcribed
/// again afterwards; that pass is the one that is kept.
@MainActor
@Observable
final class ListeningSession {
    var elapsed: TimeInterval = 0
    var levels: [CGFloat]
    var liveText = ""
    var isPaused = false
    var isRunning = false
    var failure: String?
    private(set) var bookmarks: [TimeInterval] = []

    private var engine: AVAudioEngine?
    private var file: AVAudioFile?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var recognition: SFSpeechRecognitionTask?
    private var started: Date?
    private var accumulated: TimeInterval = 0
    private var timer: Timer?
    private let url: URL
    private var finalized = ""

    init() {
        levels = Array(repeating: CGFloat(WaveformMetrics.minimumHeight), count: WaveformMetrics.barCount)
        let name = "murmur-listen-\(UUID().uuidString).m4a"
        url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
    }

    func start() async {
        failure = nil
        let mic = await Self.requestMicrophone()
        guard mic else {
            failure = "Murmur can't hear anything until the microphone is allowed."
            return
        }
        _ = await LegacyFileTranscriber.authorization()
        do {
            try configureSession()
            try startEngine()
            isRunning = true
            started = Date()
            startTimer()
        } catch {
            failure = "Listening didn't start. You can close this and try again."
            teardown()
        }
    }

    func togglePause() {
        guard isRunning else { return }
        if isPaused {
            try? engine?.start()
            isPaused = false
            startTimer()
        } else {
            engine?.pause()
            accumulated = elapsed
            timer?.invalidate()
            isPaused = true
        }
    }

    func bookmark() {
        guard isRunning else { return }
        bookmarks.append(elapsed)
        let marker = ListeningText.bookmarkMarker(at: elapsed)
        finalized += marker
        liveText += marker
    }

    func stop() -> CapturedAudio? {
        guard isRunning || file != nil else { return nil }
        timer?.invalidate()
        let duration = elapsed
        let when = started ?? Date()
        let text = liveText
        let marks = bookmarks
        teardown()
        isRunning = false
        return CapturedAudio(url: url, started: when, duration: duration, liveText: text, bookmarks: marks)
    }

    func abandon() {
        timer?.invalidate()
        teardown()
        isRunning = false
        try? FileManager.default.removeItem(at: url)
    }

    private static func requestMicrophone() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    private func configureSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.allowBluetoothHFP, .defaultToSpeaker])
        try session.setActive(true, options: .notifyOthersOnDeactivation)
    }

    private func startEngine() throws {
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw TranscribeError.unavailable
        }
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: CaptureFormat.bitRate,
        ]
        let file = try AVAudioFile(forWriting: url, settings: settings)
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true
        if let recognizer = SFSpeechRecognizer(), recognizer.isAvailable {
            recognition = recognizer.recognitionTask(with: request) { [weak self] result, _ in
                guard let result else { return }
                let piece = result.bestTranscription.formattedString
                Task { @MainActor in
                    guard let self else { return }
                    self.liveText = self.finalized + piece
                }
            }
        }
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            try? file.write(from: buffer)
            request.append(buffer)
            let power = Self.decibels(buffer)
            let height = WaveformMetrics.height(decibels: power)
            Task { @MainActor in
                guard let self, !self.isPaused else { return }
                self.levels.removeFirst()
                self.levels.append(CGFloat(height))
            }
        }
        engine.prepare()
        try engine.start()
        self.engine = engine
        self.file = file
        self.request = request
    }

    private func startTimer() {
        timer?.invalidate()
        let origin = Date()
        let base = accumulated
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, !self.isPaused else { return }
                self.elapsed = base + Date().timeIntervalSince(origin)
            }
        }
    }

    private func teardown() {
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        request?.endAudio()
        recognition?.cancel()
        engine = nil
        file = nil
        request = nil
        recognition = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private static func decibels(_ buffer: AVAudioPCMBuffer) -> Float {
        guard let samples = buffer.floatChannelData?.pointee else { return -160 }
        let count = Int(buffer.frameLength)
        guard count > 0 else { return -160 }
        var sum: Float = 0
        for index in 0..<count {
            let sample = samples[index]
            sum += sample * sample
        }
        let rms = sqrt(sum / Float(count))
        return 20 * log10(max(rms, 1e-7))
    }
}
