import Foundation
import SayWhatKit
import WhisperKit

struct Transcript {
    var text: String
    var language: DictationLanguage   // .en or .pt (resolved)
}

enum SayWhatError: LocalizedError {
    case noKey, http(String), modelNotReady, tooShort
    var errorDescription: String? {
        switch self {
        case .noKey: return "Add your Groq API key in Settings, or switch to on-device Whisper."
        case .http(let m): return m
        case .modelNotReady: return "The speech model is still loading."
        case .tooShort: return "Didn't catch that — hold a bit longer."
        }
    }
}

enum Prompts {
    /// Whisper "initial prompt" — biases spelling & punctuation. The PT one nudges European Portuguese orthography.
    static func whisper(_ lang: DictationLanguage, vocabulary: [String]) -> String {
        var p: String
        switch lang {
        case .pt: p = "Olá, tudo bem? Estou a escrever em português de Portugal, com pontuação correta: o telemóvel, o ecrã, o comboio, a receção, de facto."
        case .en: p = "Hi, how are you? This is clearly written English with proper punctuation."
        case .auto: p = "Hi, how are you? Olá, tudo bem? Português de Portugal and English."
        }
        let vocab = vocabulary.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if !vocab.isEmpty { p += " " + vocab.prefix(40).joined(separator: ", ") + "." }
        return p
    }
}

// MARK: - On-device Whisper (WhisperKit / Core ML)

final class LocalWhisper {
    static let shared = LocalWhisper()

    private var pipe: WhisperKit?
    private(set) var loadedModel: String?
    private var loading: Task<WhisperKit, Error>?

    var isReady: Bool { pipe != nil }

    /// Downloads (first time) and loads a model. `progress` reports 0...1 download progress.
    func prepare(model: String, progress: (@Sendable (Double) -> Void)? = nil) async throws {
        if loadedModel == model, pipe != nil { return }
        if let loading, loadedModel == model { _ = try await loading.value; return }
        pipe = nil
        loadedModel = model
        let task = Task { () throws -> WhisperKit in
            let folder = try await WhisperKit.download(variant: model, progressCallback: { p in
                progress?(p.fractionCompleted)
            })
            let config = WhisperKitConfig(model: model, modelFolder: folder.path, verbose: false,
                                          logLevel: .error, prewarm: true, load: true, download: false)
            return try await WhisperKit(config)
        }
        loading = task
        do {
            let kit = try await task.value
            if loadedModel == model { pipe = kit }
            loading = nil
        } catch {
            loading = nil
            loadedModel = nil
            throw error
        }
    }

    func unload() {
        pipe = nil
        loadedModel = nil
    }

    func transcribe(_ samples: [Float], language: DictationLanguage, vocabulary: [String]) async throws -> Transcript {
        guard let pipe else { throw SayWhatError.modelNotReady }

        var lang = language
        if lang == .auto {
            // Only choose between English and Portuguese, so Whisper never drifts into Spanish/Galician.
            let (_, probs) = try await pipe.detectLangauge(audioArray: Array(samples.prefix(Int(AudioRecorder.sampleRate) * 30)))
            let en = probs["en"] ?? -.infinity
            let pt = probs["pt"] ?? -.infinity
            lang = pt > en ? .pt : .en
        }

        var opts = DecodingOptions(task: .transcribe, language: lang.rawValue, temperature: 0,
                                   usePrefillPrompt: true, detectLanguage: false,
                                   skipSpecialTokens: true, withoutTimestamps: true)
        if let tok = pipe.tokenizer {
            let prompt = Prompts.whisper(lang, vocabulary: vocabulary)
            let ids = tok.encode(text: " " + prompt).filter { $0 < tok.specialTokens.specialTokenBegin }
            if !ids.isEmpty { opts.promptTokens = Array(ids.suffix(120)) }
        }
        let results = try await pipe.transcribe(audioArray: samples, decodeOptions: opts)
        let text = results.map(\.text).joined(separator: " ")
            .replacingOccurrences(of: "<|[^>]*|>", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return Transcript(text: text, language: lang)
    }
}

// MARK: - Groq (cloud Whisper large-v3-turbo + LLM)

enum Groq {
    static let base = URL(string: "https://api.groq.com/openai/v1")!

    static func transcribe(_ samples: [Float], language: DictationLanguage, vocabulary: [String], key: String) async throws -> Transcript {
        guard !key.isEmpty else { throw SayWhatError.noKey }
        var req = URLRequest(url: base.appendingPathComponent("audio/transcriptions"))
        req.httpMethod = "POST"
        req.timeoutInterval = 30
        let boundary = "SayWhat-\(UUID().uuidString)"
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        func field(_ name: String, _ value: String) {
            body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".data(using: .utf8)!)
        }
        field("model", "whisper-large-v3-turbo")
        field("response_format", "verbose_json")
        field("temperature", "0")
        field("prompt", Prompts.whisper(language, vocabulary: vocabulary))
        if language != .auto { field("language", language.rawValue) }
        body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\nContent-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
        body.append(AudioRecorder.wavData(samples))
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        req.httpBody = body

        let (data, resp) = try await URLSession.shared.data(for: req)
        try check(resp, data)
        struct R: Decodable { let text: String; let language: String? }
        let r = try JSONDecoder().decode(R.self, from: data)
        let detected = (r.language ?? "").lowercased()
        let lang: DictationLanguage = language != .auto ? language : (detected.hasPrefix("p") ? .pt : .en)
        return Transcript(text: r.text.trimmingCharacters(in: .whitespacesAndNewlines), language: lang)
    }

    static func chat(system: String, user: String, model: String, key: String) async throws -> String {
        guard !key.isEmpty else { throw SayWhatError.noKey }
        var req = URLRequest(url: base.appendingPathComponent("chat/completions"))
        req.httpMethod = "POST"
        req.timeoutInterval = 20
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let payload: [String: Any] = [
            "model": model,
            "temperature": 0.1,
            "max_tokens": 2048,
            "messages": [["role": "system", "content": system], ["role": "user", "content": user]],
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)
        let (data, resp) = try await URLSession.shared.data(for: req)
        try check(resp, data)
        struct R: Decodable { struct C: Decodable { struct M: Decodable { let content: String? }; let message: M }; let choices: [C] }
        return try JSONDecoder().decode(R.self, from: data).choices.first?.message.content ?? ""
    }

    private static func check(_ resp: URLResponse, _ data: Data) throws {
        guard let http = resp as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            struct E: Decodable { struct I: Decodable { let message: String }; let error: I }
            let msg = (try? JSONDecoder().decode(E.self, from: data))?.error.message ?? "HTTP \(http.statusCode)"
            throw SayWhatError.http(http.statusCode == 401 ? "Groq rejected the API key." : "Groq: \(msg)")
        }
    }
}
