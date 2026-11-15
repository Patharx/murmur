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

    private var rig: CaptureRig?
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
            try? rig?.engine.start()
            isPaused = false
            startTimer()
        } else {
            rig?.engine.pause()
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
        guard isRunning || rig != nil else { return nil }
        if let problem = rig?.writer.latestError(), failure == nil {
            failure = problem
        }
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
        let writer = try MonoAACWriter(url: url, input: format)
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true
        let recognition: SFSpeechRecognitionTask?
        if let recognizer = SFSpeechRecognizer(), recognizer.isAvailable {
            recognition = recognizer.recognitionTask(with: request) { [weak self] result, _ in
                guard let result else { return }
                let piece = result.bestTranscription.formattedString
                Task { @MainActor in
                    guard let self else { return }
                    self.liveText = self.finalized + piece
                }
            }
        } else {
            recognition = nil
        }
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            let converted = writer.append(buffer)
            if let converted {
                request.append(converted)
            }
            let power = Self.decibels(buffer)
            let height = WaveformMetrics.height(decibels: power)
            let problem = writer.latestError()
            Task { @MainActor in
                guard let self else { return }
                if let problem, self.failure == nil {
                    self.failure = problem
                }
                guard !self.isPaused else { return }
                self.levels.removeFirst()
                self.levels.append(CGFloat(height))
            }
        }
        engine.prepare()
        try engine.start()
        rig = CaptureRig(engine: engine, writer: writer, request: request, recognition: recognition)
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
        rig?.stop()
        rig = nil
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

/// Owns the engine so a dismissed screen still closes the file and the session.
final class CaptureRig {
    let engine: AVAudioEngine
    let writer: MonoAACWriter
    let request: SFSpeechAudioBufferRecognitionRequest
    let recognition: SFSpeechRecognitionTask?
    private var stopped = false

    init(engine: AVAudioEngine, writer: MonoAACWriter, request: SFSpeechAudioBufferRecognitionRequest, recognition: SFSpeechRecognitionTask?) {
        self.engine = engine
        self.writer = writer
        self.request = request
        self.recognition = recognition
    }

    func stop() {
        guard !stopped else { return }
        stopped = true
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        request.endAudio()
        recognition?.cancel()
        writer.close()
    }

    deinit { stop() }
}

final class MonoAACWriter {
    private let file: AVAudioFile
    private let converter: AVAudioConverter
    private let output: AVAudioFormat
    private let lock = NSLock()
    private var closed = false
    private(set) var errorMessage: String?

    init(url: URL, input: AVAudioFormat) throws {
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: CaptureFormat.sampleRate,
            AVNumberOfChannelsKey: CaptureFormat.channelCount,
            AVEncoderBitRateKey: CaptureFormat.bitRate,
        ]
        file = try AVAudioFile(forWriting: url, settings: settings)
        output = file.processingFormat
        guard let converter = AVAudioConverter(from: input, to: output) else {
            throw TranscribeError.unavailable
        }
        self.converter = converter
    }

    func append(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        lock.lock()
        defer { lock.unlock() }
        guard !closed, errorMessage == nil else { return nil }
        let ratio = output.sampleRate / max(buffer.format.sampleRate, 1)
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 64
        guard let converted = AVAudioPCMBuffer(pcmFormat: output, frameCapacity: max(capacity, 64)) else {
            errorMessage = "The audio couldn't be converted."
            return nil
        }
        var failure: NSError?
        var consumed = false
        let status = converter.convert(to: converted, error: &failure) { _, statusOut in
            if consumed {
                statusOut.pointee = .noDataNow
                return nil
            }
            consumed = true
            statusOut.pointee = .haveData
            return buffer
        }
        if status == .error || failure != nil || converted.frameLength == 0 {
            errorMessage = "The audio couldn't be converted."
            return nil
        }
        do {
            try file.write(from: converted)
        } catch {
            errorMessage = "The audio couldn't be written."
            return nil
        }
        return converted
    }

    func latestError() -> String? {
        lock.lock()
        defer { lock.unlock() }
        return errorMessage
    }

    func close() {
        lock.lock()
        closed = true
        lock.unlock()
    }
}
