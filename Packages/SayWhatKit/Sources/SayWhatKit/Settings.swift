import Foundation
#if canImport(Combine)
import Combine

/// All user settings, stored in the shared App Group so the keyboard sees them too.
public final class SettingsStore: ObservableObject {
    public static let shared = SettingsStore()
    private let d = Bridge.defaults

    @Published public var language: DictationLanguage { didSet { d.set(language.rawValue, forKey: "language") } }
    @Published public var engine: TranscriptionEngine { didSet { d.set(engine.rawValue, forKey: "engine") } }
    @Published public var localModel: String { didSet { d.set(localModel, forKey: "localModel") } }
    @Published public var polish: PolishMode { didSet { d.set(polish.rawValue, forKey: "polish") } }
    @Published public var style: WritingStyle { didSet { d.set(style.rawValue, forKey: "style") } }
    @Published public var removeFillers: Bool { didSet { d.set(removeFillers, forKey: "removeFillers") } }
    @Published public var voiceCommands: Bool { didSet { d.set(voiceCommands, forKey: "voiceCommands") } }
    @Published public var groqLLMModel: String { didSet { d.set(groqLLMModel, forKey: "groqLLMModel") } }
    @Published public var sessionMinutes: Int { didSet { d.set(sessionMinutes, forKey: "sessionMinutes") } }
    @Published public var haptics: Bool { didSet { d.set(haptics, forKey: "haptics") } }
    @Published public var autoCopy: Bool { didSet { d.set(autoCopy, forKey: "autoCopy") } }
    @Published public var macHotkey: MacHotkey { didSet { d.set(macHotkey.rawValue, forKey: "macHotkey") } }
    @Published public var vocabulary: [String] { didSet { save(vocabulary, "vocabulary") } }
    @Published public var replacements: [Replacement] { didSet { save(replacements, "replacements") } }
    @Published public var snippets: [Snippet] { didSet { save(snippets, "snippets") } }
    @Published public var onboarded: Bool { didSet { d.set(onboarded, forKey: "onboarded") } }

    public var groqKey: String {
        get { Keychain.get("groqKey") ?? "" }
        set { Keychain.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), for: "groqKey"); objectWillChange.send() }
    }

    private init() {
        language = DictationLanguage(rawValue: d.string(forKey: "language") ?? "") ?? .auto
        engine = TranscriptionEngine(rawValue: d.string(forKey: "engine") ?? "") ?? .local
        localModel = d.string(forKey: "localModel") ?? LocalModel.recommended
        polish = PolishMode(rawValue: d.string(forKey: "polish") ?? "") ?? .apple
        style = WritingStyle(rawValue: d.string(forKey: "style") ?? "") ?? .natural
        removeFillers = d.object(forKey: "removeFillers") as? Bool ?? true
        voiceCommands = d.object(forKey: "voiceCommands") as? Bool ?? true
        groqLLMModel = d.string(forKey: "groqLLMModel") ?? "llama-3.3-70b-versatile"
        sessionMinutes = d.object(forKey: "sessionMinutes") as? Int ?? 15
        haptics = d.object(forKey: "haptics") as? Bool ?? true
        autoCopy = d.object(forKey: "autoCopy") as? Bool ?? true
        macHotkey = MacHotkey(rawValue: d.string(forKey: "macHotkey") ?? "") ?? .rightOption
        onboarded = d.bool(forKey: "onboarded")
        vocabulary = Self.load([String].self, "vocabulary", d) ?? []
        replacements = Self.load([Replacement].self, "replacements", d) ?? [
            Replacement(from: "chat gpt", to: "ChatGPT"),
            Replacement(from: "say what", to: "Say What"),
        ]
        snippets = Self.load([Snippet].self, "snippets", d) ?? []
    }

    /// Re-read values written by the other process (keyboard ↔ app).
    public func reload() {
        let fresh = DictationLanguage(rawValue: d.string(forKey: "language") ?? "") ?? .auto
        if fresh != language { language = fresh }
    }

    public var cleanerOptions: TextCleaner.Options {
        TextCleaner.Options(removeFillers: removeFillers, voiceCommands: voiceCommands, style: style,
                            replacements: replacements, snippets: snippets)
    }

    private func save<T: Encodable>(_ v: T, _ key: String) {
        if let data = try? JSONEncoder().encode(v) { d.set(data, forKey: key) }
    }
    private static func load<T: Decodable>(_ t: T.Type, _ key: String, _ d: UserDefaults) -> T? {
        guard let data = d.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(t, from: data)
    }
}
#endif
