import Foundation

/// Instant, rule-based cleanup for raw Whisper output in English and European Portuguese.
/// Runs before (and as a fallback for) the optional AI polish step.
public enum TextCleaner {

    public struct Options {
        public var removeFillers = true
        public var voiceCommands = true
        public var style: WritingStyle = .natural
        public var replacements: [Replacement] = []
        public var snippets: [Snippet] = []
        public init(removeFillers: Bool = true, voiceCommands: Bool = true, style: WritingStyle = .natural,
                    replacements: [Replacement] = [], snippets: [Snippet] = []) {
            self.removeFillers = removeFillers
            self.voiceCommands = voiceCommands
            self.style = style
            self.replacements = replacements
            self.snippets = snippets
        }
    }

    /// Phrases Whisper hallucinates on silence / noise.
    static let hallucinations: Set<String> = [
        "thank you", "thanks for watching", "thank you for watching", "thanks for watching!", "you",
        "bye", "obrigado", "obrigada", "obrigado por assistir", "legendas pela comunidade amara.org",
        "subtitles by the amara.org community", "legenda adriana zanotto", "tchau", "...",
    ]

    public static func isHallucination(_ text: String) -> Bool {
        let t = text.lowercased().trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))
        return t.isEmpty || hallucinations.contains(t)
    }

    // Word boundary that understands accented letters (ICU \b is Unicode-aware, but we keep it explicit).
    private static let L = "\\p{L}"

    public static func clean(_ raw: String, options: Options = Options()) -> String {
        var s = raw.replacingOccurrences(of: "\u{00A0}", with: " ")
        s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if isHallucination(s) { return "" }

        // Strip Whisper bracket annotations like [Music], (risos), [BLANK_AUDIO]
        s = rx(s, "\\s*[\\[(](?:music|música|musica|risos|laughter|laughs|applause|aplausos|blank_audio|silence|silêncio|inaudible|inaudível)[\\])]\\s*", " ", caseInsensitive: true)

        if options.voiceCommands { s = applyVoiceCommands(s) }
        if options.removeFillers { s = removeFillers(s) }
        s = removeStutters(s)
        s = applyReplacements(s, options.replacements)
        s = applySnippets(s, options.snippets)
        s = tidyPunctuation(s)
        s = applyStyle(s, options.style)
        return s
    }

    // MARK: Voice commands

    static func applyVoiceCommands(_ input: String) -> String {
        var s = input
        // "scratch that" / "apaga isso": drop the sentence (or clause) before it
        let scratch = "(?:scratch that|delete that|apaga isso|apaga isto|esquece isso|esquece isto)"
        s = rx(s, "[^.!?\\n]+[.!?,]?\\s*\\b\(scratch)\\b[,.!?]?\\s*", " ", caseInsensitive: true)

        let lead = "[ \\t,]*"
        let trail = "[,.;:]?[ \\t]*"
        s = rx(s, "\(lead)\\b(?:new paragraph|novo parágrafo|novo paragrafo)\\b\(trail)", "\n\n", caseInsensitive: true)
        s = rx(s, "\(lead)\\b(?:new line|next line|nova linha|próxima linha|proxima linha)\\b\(trail)", "\n", caseInsensitive: true)
        s = rx(s, "[\\s,]*\\b(?:full stop|ponto final)\\b[.,]?", ".", caseInsensitive: true)
        s = rx(s, "[\\s,]*\\b(?:question mark|ponto de interrogação|ponto de interrogacao)\\b[.,?]?", "?", caseInsensitive: true)
        s = rx(s, "[\\s,]*\\b(?:exclamation mark|exclamation point|ponto de exclamação|ponto de exclamacao)\\b[.,!]?", "!", caseInsensitive: true)
        s = rx(s, "[\\s]*\\b(?:comma|vírgula|virgula)\\b[.,]?", ",", caseInsensitive: true)
        return s
    }

    // MARK: Fillers & stutters

    static let fillerWords = [
        "um+", "uh+", "uhm+", "umm+", "erm+", "er", "hmm+", "mmm+", "mhm",       // EN
        "hã+", "ãh+", "hum+", "humm+", "eh+", "éh+", "ahn", "ã+",                // PT
    ]

    static func removeFillers(_ input: String) -> String {
        let alt = fillerWords.joined(separator: "|")
        // filler possibly followed by comma/period/ellipsis
        var s = rx(input, "(?<!\(L))(?:\(alt))(?!\(L))(?:\\.\\.\\.|…|[,.])?\\s*", "", caseInsensitive: true)
        // English "you know," / "I mean," at clause starts, PT "tipo," / "pronto," as hedges between commas
        s = rx(s, "(^|[.!?]\\s+|,\\s*)(?:you know|i mean|like|tipo|pronto),\\s*", "$1", caseInsensitive: true)
        return s
    }

    static func removeStutters(_ input: String) -> String {
        // "I I think" → "I think", "eu eu acho" → "eu acho" (also with commas between)
        rx(input, "(?<!\(L))(\(L)+)(?:\\s+\\1)+(?!\(L))", "$1", caseInsensitive: true)
    }

    // MARK: Dictionary & snippets

    static func applyReplacements(_ input: String, _ reps: [Replacement]) -> String {
        var s = input
        for r in reps where !r.from.trimmingCharacters(in: .whitespaces).isEmpty {
            let pattern = "(?<!\(L))" + NSRegularExpression.escapedPattern(for: r.from.trimmingCharacters(in: .whitespaces)) + "(?!\(L))"
            s = rx(s, pattern, NSRegularExpression.escapedTemplate(for: r.to), caseInsensitive: true)
        }
        return s
    }

    static func applySnippets(_ input: String, _ snippets: [Snippet]) -> String {
        var s = input
        for sn in snippets where !sn.trigger.trimmingCharacters(in: .whitespaces).isEmpty {
            let pattern = "(?<!\(L))" + NSRegularExpression.escapedPattern(for: sn.trigger.trimmingCharacters(in: .whitespaces)) + "(?!\(L))[.!]?"
            s = rx(s, pattern, NSRegularExpression.escapedTemplate(for: sn.text), caseInsensitive: true)
        }
        return s
    }

    // MARK: Punctuation, spacing, capitals

    static func tidyPunctuation(_ input: String) -> String {
        var s = input
        s = rx(s, "[ \\t]+", " ")
        s = rx(s, " *\\n *", "\n")
        s = rx(s, "\\n{3,}", "\n\n")
        s = rx(s, " +([.!?])(?=\\p{L})", "$1 ")
        s = rx(s, " +([,.!?;:…])", "$1")
        s = rx(s, "([,;:])(?=\\p{L})", "$1 ")
        s = rx(s, "(?<=\\p{Ll})([.!?])(?=\\p{Lu})", "$1 ")
        s = rx(s, ",{2,}", ",")
        s = rx(s, "([.!?]),", "$1")
        s = rx(s, ",([.!?])", "$1")
        s = rx(s, "(?<!\\.)\\.\\.(?!\\.)", ".")
        s = rx(s, "^[\\s,.;:]+", "")
        s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        s = capitalizeSentences(s)
        // standalone English "i"
        s = rx(s, "(?<!\(L))i(?=(?:['’](?:m|d|ll|ve))?(?!\(L)))", "I")
        return s
    }

    static func capitalizeSentences(_ input: String) -> String {
        var out = ""
        var capNext = true
        var sawStop = false
        for ch in input {
            if sawStop {
                sawStop = false
                if ch.isWhitespace { capNext = true }
            }
            if capNext, ch.isLetter {
                out += String(ch).uppercased()
                capNext = false
                continue
            }
            out.append(ch)
            if ch == "\n" { capNext = true }
            else if ".!?".contains(ch) { sawStop = true }
            else if !ch.isWhitespace && !"\"'“”«»([".contains(ch) { capNext = false }
        }
        return out
    }

    static func applyStyle(_ input: String, _ style: WritingStyle) -> String {
        guard !input.isEmpty else { return input }
        switch style {
        case .natural:
            return input
        case .formal:
            if let last = input.last, !".!?…:".contains(last) { return input + "." }
            return input
        case .casual:
            var s = input
            if s.hasSuffix("."), !s.hasSuffix("...") { s.removeLast() }
            s = lowercaseFirstWord(s)
            return s
        }
    }

    // MARK: Regex helper

    static func rx(_ s: String, _ pattern: String, _ template: String, caseInsensitive: Bool = false) -> String {
        guard let re = try? NSRegularExpression(pattern: pattern, options: caseInsensitive ? [.caseInsensitive] : []) else { return s }
        return re.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: template)
    }

    // MARK: Smart insertion (used by the keyboard and Mac paster)

    /// Adjusts spacing / capitalisation of `text` so it flows after `before` (text left of the cursor).
    public static func fit(_ text: String, after before: String?) -> String {
        guard !text.isEmpty, let before, let last = before.last else { return text }
        var t = text
        let lastSignificant = before.trimmingCharacters(in: .whitespaces).last
        let atSentenceStart = lastSignificant == nil || ".!?\n:".contains(lastSignificant!)
        if !atSentenceStart { t = lowercaseFirstWord(t) }
        let noSpaceBefore = ",.;:!?)]}…"
        let noSpaceAfter = "([{\"'“«/-\n"
        if !last.isWhitespace, !noSpaceBefore.contains(t.first ?? " "), !noSpaceAfter.contains(last) {
            t = " " + t
        }
        return t
    }

    /// Lowercases the first letter unless the first word is "I", an acronym, or a name-looking word we can't judge.
    static func lowercaseFirstWord(_ text: String) -> String {
        guard let first = text.first, first.isUppercase else { return text }
        let word = text.prefix { $0.isLetter || $0 == "'" || $0 == "’" }
        let letters = word.filter { $0.isLetter }
        if letters == "I" || word.hasPrefix("I'") || word.hasPrefix("I’") { return text }
        if letters.count > 1 && letters.allSatisfy({ $0.isUppercase }) { return text }
        return first.lowercased() + text.dropFirst()
    }
}
