import AVFoundation
import Foundation

/// Captures microphone audio and delivers 16 kHz mono Float samples (what Whisper wants).
/// The engine can be kept "warm" (running) between recordings — that's how the iOS keyboard
/// session works: the app keeps the engine alive in the background and only stores samples
/// while a capture is active.
final class AudioRecorder {
    static let sampleRate: Double = 16_000

    private let engine = AVAudioEngine()
    private var converter: AVAudioConverter?
    private let targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: AudioRecorder.sampleRate, channels: 1, interleaved: false)!
    private let lock = NSLock()
    private var samples: [Float] = []
    private var capturing = false
    private(set) var isRunning = false

    /// Called on the audio thread with an RMS level in 0...1.
    var onLevel: ((Float) -> Void)?

    // MARK: Permissions

    static func requestPermission() async -> Bool {
        #if os(iOS)
        if #available(iOS 17.0, *) {
            return await AVAudioApplication.requestRecordPermission()
        }
        return false
        #else
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .audio)
        default: return false
        }
        #endif
    }

    // MARK: Engine

    func startEngine() throws {
        guard !isRunning else { return }
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .measurement,
                                options: [.mixWithOthers, .defaultToSpeaker, .allowBluetooth])
        try session.setActive(true, options: [])
        #endif
        let input = engine.inputNode
        let inFormat = input.outputFormat(forBus: 0)
        guard inFormat.sampleRate > 0, inFormat.channelCount > 0 else {
            throw NSError(domain: "SayWhat", code: 1, userInfo: [NSLocalizedDescriptionKey: "No microphone input available"])
        }
        converter = AVAudioConverter(from: inFormat, to: targetFormat)
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 2048, format: inFormat) { [weak self] buffer, _ in
            self?.process(buffer)
        }
        engine.prepare()
        try engine.start()
        isRunning = true
    }

    func stopEngine() {
        guard isRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRunning = false
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        #endif
    }

    // MARK: Capture

    func beginCapture() {
        lock.lock(); samples.removeAll(keepingCapacity: true); capturing = true; lock.unlock()
    }

    func endCapture() -> [Float] {
        lock.lock(); capturing = false; let out = samples; samples.removeAll(); lock.unlock()
        return out
    }

    private func process(_ buffer: AVAudioPCMBuffer) {
        // Level meter (works whether or not we're capturing so the UI can show "mic is live")
        if let ch = buffer.floatChannelData?[0] {
            let n = Int(buffer.frameLength)
            var sum: Float = 0
            for i in 0..<n { sum += ch[i] * ch[i] }
            let rms = n > 0 ? sqrt(sum / Float(n)) : 0
            onLevel?(min(1, rms * 12))
        }
        lock.lock(); let isCapturing = capturing; lock.unlock()
        guard isCapturing, let converter else { return }

        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio + 32)
        guard let out = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return }
        var fed = false
        var error: NSError?
        converter.convert(to: out, error: &error) { _, status in
            if fed { status.pointee = .noDataNow; return nil }
            fed = true
            status.pointee = .haveData
            return buffer
        }
        guard error == nil, let data = out.floatChannelData?[0] else { return }
        let chunk = Array(UnsafeBufferPointer(start: data, count: Int(out.frameLength)))
        lock.lock(); if capturing { samples.append(contentsOf: chunk) }; lock.unlock()
    }

    // MARK: Utils

    static func rms(_ s: [Float]) -> Float {
        guard !s.isEmpty else { return 0 }
        var sum: Float = 0
        for x in s { sum += x * x }
        return sqrt(sum / Float(s.count))
    }

    /// 16-bit PCM WAV for cloud transcription.
    static func wavData(_ s: [Float]) -> Data {
        var d = Data()
        let sr = UInt32(sampleRate)
        let dataSize = UInt32(s.count * 2)
        func u32(_ v: UInt32) { var x = v.littleEndian; d.append(Data(bytes: &x, count: 4)) }
        func u16(_ v: UInt16) { var x = v.littleEndian; d.append(Data(bytes: &x, count: 2)) }
        d.append("RIFF".data(using: .ascii)!); u32(36 + dataSize)
        d.append("WAVE".data(using: .ascii)!)
        d.append("fmt ".data(using: .ascii)!); u32(16); u16(1); u16(1); u32(sr); u32(sr * 2); u16(2); u16(16)
        d.append("data".data(using: .ascii)!); u32(dataSize)
        var pcm = [Int16](repeating: 0, count: s.count)
        for i in 0..<s.count { pcm[i] = Int16(max(-1, min(1, s[i])) * 32767) }
        pcm.withUnsafeBufferPointer { d.append(Data(buffer: $0)) }
        return d
    }
}
