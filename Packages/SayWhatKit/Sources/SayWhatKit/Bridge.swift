import Foundation

/// Shared state + signalling between the Say What app and the Say What keyboard.
/// The keyboard cannot use the microphone (iOS rule), so the app owns a "session":
/// it keeps the audio engine warm in the background and the keyboard drives it
/// through Darwin notifications + App Group defaults.
public enum Bridge {
    public static let appGroup = "group.com.afonsopedroso.saywhat"
    public static let urlScheme = "saywhat"

    public static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroup) ?? .standard
    }

    public enum Key {
        public static let heartbeat = "bridge.heartbeat"       // Double, unix time; app writes every second while a session is alive
        public static let state = "bridge.state"               // SessionState.rawValue
        public static let level = "bridge.level"               // Float 0...1, mic level while recording
        public static let resultText = "bridge.resultText"
        public static let resultID = "bridge.resultID"
        public static let error = "bridge.error"
        public static let sessionEnds = "bridge.sessionEnds"   // Double, unix time
    }

    public enum Note {
        public static let start = "com.afonsopedroso.saywhat.start"
        public static let stop = "com.afonsopedroso.saywhat.stop"
        public static let cancel = "com.afonsopedroso.saywhat.cancel"
        public static let result = "com.afonsopedroso.saywhat.result"
        public static let state = "com.afonsopedroso.saywhat.state"
    }

    public enum SessionState: String {
        case off, idle, recording, transcribing
    }

    // MARK: State helpers

    public static var isSessionAlive: Bool {
        let hb = defaults.double(forKey: Key.heartbeat)
        return hb > 0 && Date().timeIntervalSince1970 - hb < 3.5
    }

    public static var state: SessionState {
        get { isSessionAlive ? SessionState(rawValue: defaults.string(forKey: Key.state) ?? "") ?? .idle : .off }
        set { defaults.set(newValue.rawValue, forKey: Key.state); post(Note.state) }
    }

    public static func publishResult(_ text: String) {
        defaults.set(text, forKey: Key.resultText)
        defaults.set(UUID().uuidString, forKey: Key.resultID)
        defaults.removeObject(forKey: Key.error)
        post(Note.result)
    }

    public static func publishError(_ message: String) {
        defaults.set(message, forKey: Key.error)
        defaults.set(UUID().uuidString, forKey: Key.resultID)
        defaults.set("", forKey: Key.resultText)
        post(Note.result)
    }

    // MARK: Darwin notifications

    public static func post(_ name: String) {
        #if canImport(Darwin)
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        CFNotificationCenterPostNotification(center, CFNotificationName(name as CFString), nil, nil, true)
        #endif
    }
}

#if canImport(Darwin)
/// Observes cross-process Darwin notifications and calls handlers on the main queue.
public final class DarwinObserver {
    private var handlers: [String: () -> Void] = [:]

    public init() {}

    public func observe(_ name: String, handler: @escaping () -> Void) {
        handlers[name] = handler
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        let observer = Unmanaged.passUnretained(self).toOpaque()
        CFNotificationCenterAddObserver(center, observer, { _, observer, name, _, _ in
            guard let observer, let name else { return }
            let me = Unmanaged<DarwinObserver>.fromOpaque(observer).takeUnretainedValue()
            let key = name.rawValue as String
            DispatchQueue.main.async { me.handlers[key]?() }
        }, name as CFString, nil, .deliverImmediately)
    }

    public func removeAll() {
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        CFNotificationCenterRemoveEveryObserver(center, Unmanaged.passUnretained(self).toOpaque())
        handlers.removeAll()
    }

    deinit { removeAll() }
}
#endif
