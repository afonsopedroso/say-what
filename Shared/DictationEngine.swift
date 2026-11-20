import Foundation
import SayWhatKit
import Combine

struct HistoryItem: Codable, Identifiable, Hashable {
    var id = UUID()
    var date = Date()
    var text: String
    var raw: String
    var language: String
    var seconds: Double
}

final class HistoryStore: ObservableObject {
    static let shared = HistoryStore()
    @Published private(set) var items: [HistoryItem] = []
    private let url: URL

    private init() {
        let dir = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Bridge.appGroup)
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        url = dir.appendingPathComponent("history.json")
        if let data = try? Data(contentsOf: url), let v = try? JSONDecoder().decode([HistoryItem].self, from: data) { items = v }
    }

    func add(_ item: HistoryItem) {
        items.insert(item, at: 0)
        if items.count > 500 { items.removeLast(items.count - 500) }
        save()
    }
    func delete(_ item: HistoryItem) { items.removeAll { $0.id == item.id }; save() }
    func clear() { items.removeAll(); save() }

    var totalWords: Int { items.reduce(0) { $0 + $1.text.split(separator: " ").count } }
    var totalSeconds: Double { items.reduce(0) { $0 + $1.seconds } }
    /// Speaking ~150 wpm vs typing ~40 wpm (phone) — rough minutes saved.
    var minutesSaved: Int { max(0, Int(Double(totalWords) / 40.0 - totalSeconds / 60.0)) }

    private func save() {
        if let data = try? JSONEncoder().encode(items) { try? data.write(to: url, options: .atomic) }
    }
}

/// Orchestrates record → transcribe → clean → polish. Shared by the iOS app, its keyboard session, and the Mac app.
@MainActor
final class DictationEngine: ObservableObject {
    static let shared = DictationEngine()

    enum Phase: Equatable { case idle, recording, transcribing, polishing }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var level: Float = 0
    @Published private(set) var lastText: String = ""
    @Published var errorMessage: String?
    @Published private(set) var modelProgress: Double = 0
    @Published private(set) var modelState: String = "Not loaded"
    @Published private(set) var modelReady = false

    let recorder = AudioRecorder()
    let settings = SettingsStore.shared
    private var startedAt = Date()
    private var keepEngineWarm = false
    var levelSink: ((Float) -> Void)?

    private init() {
        recorder.onLevel = { [weak self] l in
            DispatchQueue.main.async {
                guard let self else { return }
                self.level = self.level * 0.6 + l * 0.4
                self.levelSink?(self.level)
            }
        }
    }

    // MARK: Model

    func prepareModel() async {
        guard settings.engine == .local else { modelReady = true; modelState = "Using Groq"; return }
        let model = settings.localModel
        if LocalWhisper.shared.isReady, LocalWhisper.shared.loadedModel == model { modelReady = true; return }
        modelReady = false
        modelState = "Downloading \(LocalModel.named(model).name)…"
        modelProgress = 0
        do {
            try await LocalWhisper.shared.prepare(model: model) { p in
                Task { @MainActor in
                    self.modelProgress = p
                    if p >= 0.999 { self.modelState = "Optimising for this device (first time only)…" }
                }
            }
            modelReady = LocalWhisper.shared.loadedModel == model
            modelState = modelReady ? "\(LocalModel.named(model).name) ready" : modelState
        } catch {
            modelState = "Model failed: \(error.localizedDescription)"
            errorMessage = modelState
        }
    }

    // MARK: Recording

    /// - Parameter warm: keep the audio engine running after this recording (keyboard session / Mac).
    func start(warm: Bool = false) {
        guard phase == .idle else { return }
        errorMessage = nil
        keepEngineWarm = warm || keepEngineWarm
        do {
            try recorder.startEngine()
        } catch {
            errorMessage = "Microphone error: \(error.localizedDescription)"
            return
        }
        recorder.beginCapture()
        startedAt = Date()
        phase = .recording
        if settings.engine == .local && !modelReady { Task { await prepareModel() } }
    }

    func cancel() {
        guard phase == .recording else { return }
        _ = recorder.endCapture()
        phase = .idle
        if !keepEngineWarm { recorder.stopEngine() }
    }

    func setWarm(_ warm: Bool) {
        keepEngineWarm = warm
        if warm { try? recorder.startEngine() }
        else if phase == .idle { recorder.stopEngine() }
    }

    /// Stops recording and returns final text ("" if nothing was said).
    @discardableResult
    func stop() async -> String {
        guard phase == .recording else { return "" }
        let samples = recorder.endCapture()
        if !keepEngineWarm { recorder.stopEngine() }
        let seconds = Date().timeIntervalSince(startedAt)

        guard samples.count > Int(AudioRecorder.sampleRate * 0.35) else {
            phase = .idle
            return ""
        }
        guard AudioRecorder.rms(samples) > 0.004 else {   // silence → Whisper would hallucinate
            phase = .idle
            return ""
        }
        phase = .transcribing
        do {
            let transcript: Transcript
            switch settings.engine {
            case .groq:
                transcript = try await Groq.transcribe(samples, language: settings.language,
                                                       vocabulary: settings.vocabulary, key: settings.groqKey)
            case .local:
                if !LocalWhisper.shared.isReady || LocalWhisper.shared.loadedModel != settings.localModel {
                    await prepareModel()
                }
                transcript = try await LocalWhisper.shared.transcribe(samples, language: settings.language,
                                                                      vocabulary: settings.vocabulary)
            }
            var text = TextCleaner.clean(transcript.text, options: settings.cleanerOptions)
            if !text.isEmpty, settings.polish != .rules {
                phase = .polishing
                if let polished = await Polisher.polish(text, language: transcript.language, settings: settings) {
                    // re-apply dictionary + snippets + style after the model
                    text = TextCleaner.clean(polished, options: settings.cleanerOptions)
                }
            }
            phase = .idle
            if !text.isEmpty {
                lastText = text
                HistoryStore.shared.add(HistoryItem(text: text, raw: transcript.text,
                                                    language: transcript.language.rawValue, seconds: seconds))
            }
            return text
        } catch {
            phase = .idle
            errorMessage = error.localizedDescription
            return ""
        }
    }
}
