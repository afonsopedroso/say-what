import AVFoundation
import Foundation
import SayWhatKit
import UIKit

/// A Wispr-style "Flow session": the app keeps the microphone engine warm in the background so the
/// Say What keyboard (which iOS forbids from using the mic) can start/stop dictation instantly.
@MainActor
final class KeyboardSession: ObservableObject {
    static let shared = KeyboardSession()

    @Published private(set) var active = false
    @Published private(set) var endsAt: Date?
    @Published var showHandoff = false   // full-screen "swipe back" hint after the keyboard opened us

    private let observer = DarwinObserver()
    private var ticker: Timer?
    private let engine = DictationEngine.shared
    private let settings = SettingsStore.shared

    private init() {
        NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  AVAudioSession.InterruptionType(rawValue: raw) == .began else { return }
            Task { @MainActor in self?.end() }
        }
    }

    func handle(url: URL) {
        guard url.scheme == Bridge.urlScheme else { return }
        switch url.host {
        case "dictate":
            begin(recordNow: true)
            showHandoff = true
        case "session":
            begin(recordNow: false)
            showHandoff = true
        case "stop":
            end()
        default:
            break
        }
    }

    func begin(recordNow: Bool) {
        if !active {
            observer.observe(Bridge.Note.start) { [weak self] in self?.handleStart() }
            observer.observe(Bridge.Note.stop) { [weak self] in self?.handleStop() }
            observer.observe(Bridge.Note.cancel) { [weak self] in self?.handleCancel() }
            engine.setWarm(true)
            active = true
            Bridge.state = .idle
            ticker = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.tick() }
            }
            Task { await engine.prepareModel() }
        }
        extend()
        tick()
        if recordNow { handleStart() }
    }

    func end() {
        guard active else { return }
        if engine.phase == .recording { engine.cancel() }
        ticker?.invalidate(); ticker = nil
        observer.removeAll()
        engine.setWarm(false)
        active = false
        endsAt = nil
        Bridge.defaults.set(0, forKey: Bridge.Key.heartbeat)
        Bridge.defaults.set(Bridge.SessionState.off.rawValue, forKey: Bridge.Key.state)
        Bridge.post(Bridge.Note.state)
    }

    private func extend() {
        let end = Date().addingTimeInterval(TimeInterval(settings.sessionMinutes * 60))
        endsAt = end
        Bridge.defaults.set(end.timeIntervalSince1970, forKey: Bridge.Key.sessionEnds)
    }

    private func tick() {
        guard active else { return }
        let d = Bridge.defaults
        d.set(Date().timeIntervalSince1970, forKey: Bridge.Key.heartbeat)
        d.set(engine.phase == .recording ? engine.level : 0, forKey: Bridge.Key.level)
        if let endsAt, Date() > endsAt, engine.phase == .idle { end() }
    }

    private func handleStart() {
        guard active, engine.phase == .idle else { return }
        extend()
        engine.start(warm: true)
        if engine.phase == .recording {
            Bridge.state = .recording
        } else {
            Bridge.publishError(engine.errorMessage ?? "Couldn't start the microphone")
            Bridge.state = .idle
        }
    }

    private func handleStop() {
        guard engine.phase == .recording else { return }
        Bridge.state = .transcribing
        Task {
            let text = await engine.stop()
            if text.isEmpty {
                Bridge.publishError(engine.errorMessage ?? "")
            } else {
                Bridge.publishResult(text)
            }
            Bridge.state = .idle
            extend()
        }
    }

    private func handleCancel() {
        engine.cancel()
        Bridge.state = .idle
    }
}
