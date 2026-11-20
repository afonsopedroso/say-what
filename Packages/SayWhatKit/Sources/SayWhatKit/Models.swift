import Foundation

public enum DictationLanguage: String, CaseIterable, Identifiable, Codable {
    case auto, en, pt
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .auto: return "Auto (EN / PT)"
        case .en: return "English"
        case .pt: return "Português (PT)"
        }
    }
    public var short: String {
        switch self {
        case .auto: return "AUTO"
        case .en: return "EN"
        case .pt: return "PT"
        }
    }
    public var next: DictationLanguage {
        switch self {
        case .auto: return .en
        case .en: return .pt
        case .pt: return .auto
        }
    }
}

public enum TranscriptionEngine: String, CaseIterable, Identifiable, Codable {
    case local, groq
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .local: return "On-device Whisper (private, offline)"
        case .groq: return "Groq Turbo (cloud, fastest)"
        }
    }
}

public enum PolishMode: String, CaseIterable, Identifiable, Codable {
    case rules, apple, groq
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .rules: return "Rules only (instant)"
        case .apple: return "Apple on-device AI"
        case .groq: return "Groq AI (best for PT-PT)"
        }
    }
}

public enum WritingStyle: String, CaseIterable, Identifiable, Codable {
    case natural, formal, casual
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .natural: return "Natural"
        case .formal: return "Formal"
        case .casual: return "Casual (texting)"
        }
    }
}

public struct LocalModel: Identifiable, Hashable {
    public let id: String
    public let name: String
    public let size: String
    public let note: String

    public static let all: [LocalModel] = [
        LocalModel(id: "openai_whisper-tiny", name: "Tiny", size: "~75 MB", note: "Fastest, rough on Portuguese"),
        LocalModel(id: "openai_whisper-base", name: "Base", size: "~145 MB", note: "Fast, OK quality"),
        LocalModel(id: "openai_whisper-small_216MB", name: "Small", size: "~216 MB", note: "Best balance — recommended"),
        LocalModel(id: "openai_whisper-large-v3-v20240930_turbo_632MB", name: "Large v3 Turbo", size: "~632 MB", note: "Best accuracy · iPhone 15 Pro+ / any Apple-silicon Mac"),
    ]
    public static let recommended = "openai_whisper-small_216MB"

    public static func named(_ id: String) -> LocalModel {
        all.first { $0.id == id } ?? all[2]
    }
}

public struct Replacement: Codable, Hashable, Identifiable {
    public var id = UUID()
    public var from: String
    public var to: String
    public init(from: String, to: String) { self.from = from; self.to = to }
}

public struct Snippet: Codable, Hashable, Identifiable {
    public var id = UUID()
    public var trigger: String
    public var text: String
    public init(trigger: String, text: String) { self.trigger = trigger; self.text = text }
}

public enum MacHotkey: String, CaseIterable, Identifiable, Codable {
    case rightOption, rightCommand, fn, rightControl
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .rightOption: return "Right ⌥ Option"
        case .rightCommand: return "Right ⌘ Command"
        case .fn: return "fn / 🌐"
        case .rightControl: return "Right ⌃ Control"
        }
    }
    public var keyCode: UInt16 {
        switch self {
        case .rightOption: return 61
        case .rightCommand: return 54
        case .fn: return 63
        case .rightControl: return 62
        }
    }
}

