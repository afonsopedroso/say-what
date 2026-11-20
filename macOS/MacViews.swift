import AppKit
import SwiftUI
import SayWhatKit

private let accent = Color(red: 1.0, green: 0.30, blue: 0.20)

// MARK: - Floating HUD pill

@MainActor
final class HUDController: ObservableObject {
    enum Mode { case listening, working, message }
    @Published var mode: Mode = .listening
    @Published var level: Float = 0
    @Published var handsFree = false
    @Published var text = ""
    private var panel: NSPanel?

    func show(_ m: Mode) {
        mode = m
        if panel == nil { build() }
        position()
        panel?.orderFrontRegardless()
    }

    func hide() { panel?.orderOut(nil) }

    func flash(_ message: String) {
        text = message
        show(.message)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            if self?.mode == .message { self?.hide() }
        }
    }

    private func build() {
        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 260, height: 56),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isFloatingPanel = true
        p.level = .statusBar
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = false
        p.ignoresMouseEvents = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        p.contentView = NSHostingView(rootView: HUDView(hud: self))
        panel = p
    }

    private func position() {
        guard let panel, let screen = NSScreen.main else { return }
        let f = screen.visibleFrame
        panel.setFrameOrigin(NSPoint(x: f.midX - panel.frame.width / 2, y: f.minY + 28))
    }
}

struct HUDView: View {
    @ObservedObject var hud: HUDController

    var body: some View {
        HStack(spacing: 10) {
            switch hud.mode {
            case .listening:
                Circle().fill(accent).frame(width: 10, height: 10)
                Bars(level: hud.level)
                Text(hud.handsFree ? "Hands-free · tap key to finish" : "Listening")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
            case .working:
                ProgressView().controlSize(.small).tint(.white)
                Text("Writing…").font(.system(size: 12, weight: .semibold, design: .rounded))
            case .message:
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text(hud.text).font(.system(size: 11)).lineLimit(2)
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .frame(height: 40)
        .background(Capsule().fill(Color.black.opacity(0.86)))
        .overlay(Capsule().stroke(Color.white.opacity(0.12)))
        .frame(width: 260, height: 56)
    }
}

struct Bars: View {
    var level: Float
    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<9, id: \.self) { i in
                let wave = abs(sin(Double(i) * 0.9)) * 0.6 + 0.4
                Capsule().fill(Color.white)
                    .frame(width: 3, height: max(4, CGFloat(Double(level) * wave) * 26))
            }
        }
        .animation(.easeOut(duration: 0.1), value: level)
        .frame(height: 26)
    }
}

// MARK: - Menu bar window

struct MenuView: View {
    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject var engine: DictationEngine
    @EnvironmentObject var history: HistoryStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "quote.bubble.fill").foregroundStyle(accent)
                Text("Say What").font(.system(size: 16, weight: .heavy, design: .rounded))
                Spacer()
                Picker("", selection: $settings.language) {
                    ForEach(DictationLanguage.allCases) { Text($0.short).tag($0) }
                }
                .pickerStyle(.segmented).frame(width: 150)
            }
            Text("Hold \(settings.macHotkey.label) and talk. Release to paste. Quick tap = hands-free. Esc cancels.")
                .font(.caption).foregroundStyle(.secondary)

            if !Accessibility.trusted {
                Button {
                    Accessibility.prompt()
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                } label: {
                    Label("Allow Accessibility so Say What can paste", systemImage: "hand.raised.fill")
                }
                .buttonStyle(.borderedProminent)
            }

            if settings.engine == .local && !engine.modelReady {
                VStack(alignment: .leading, spacing: 4) {
                    ProgressView(value: engine.modelProgress)
                    Text(engine.modelState).font(.caption2).foregroundStyle(.secondary)
                }
            }
            if let err = engine.errorMessage {
                Text(err).font(.caption).foregroundStyle(.orange)
            }

            Divider()
            Text("Recent").font(.caption.bold()).foregroundStyle(.secondary)
            if history.items.isEmpty {
                Text("Nothing yet.").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(history.items.prefix(5)) { item in
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(item.text, forType: .string)
                } label: {
                    Text(item.text).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .help("Click to copy")
            }
            Divider()
            HStack {
                Text("\(history.totalWords) words · \(history.minutesSaved) min saved")
                    .font(.caption2).foregroundStyle(.secondary)
                Spacer()
                SettingsLink { Text("Settings…") }
                Button("Quit") { NSApp.terminate(nil) }
            }
        }
        .padding(16)
        .frame(width: 340)
    }
}

struct MacSettingsView: View {
    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject var engine: DictationEngine
    @State private var key = SettingsStore.shared.groqKey
    @State private var newWord = ""
    @State private var from = ""
    @State private var to = ""

    var body: some View {
        Form {
            Section("Dictation") {
                Picker("Language", selection: $settings.language) {
                    ForEach(DictationLanguage.allCases) { Text($0.label).tag($0) }
                }
                Picker("Hotkey (hold to talk)", selection: $settings.macHotkey) {
                    ForEach(MacHotkey.allCases) { Text($0.label).tag($0) }
                }
                Picker("Engine", selection: $settings.engine) {
                    ForEach(TranscriptionEngine.allCases) { Text($0.label).tag($0) }
                }
                if settings.engine == .local {
                    Picker("Model", selection: $settings.localModel) {
                        ForEach(LocalModel.all) { Text("\($0.name) · \($0.size)").tag($0.id) }
                    }
                    Text(engine.modelState).font(.caption).foregroundStyle(.secondary)
                }
            }
            .onChange(of: settings.localModel) { _, _ in Task { await engine.prepareModel() } }
            .onChange(of: settings.engine) { _, _ in Task { await engine.prepareModel() } }

            Section("Clean-up") {
                Picker("AI polish", selection: $settings.polish) {
                    ForEach(PolishMode.allCases) { Text($0.label).tag($0) }
                }
                Picker("Style", selection: $settings.style) {
                    ForEach(WritingStyle.allCases) { Text($0.label).tag($0) }
                }
                Toggle("Remove filler words", isOn: $settings.removeFillers)
                Toggle("Voice commands (new line, ponto final…)", isOn: $settings.voiceCommands)
                Toggle("Leave dictation on the clipboard", isOn: $settings.autoCopy)
            }

            Section("Groq (optional)") {
                SecureField("API key", text: $key).onChange(of: key) { _, v in settings.groqKey = v }
                TextField("LLM model", text: $settings.groqLLMModel)
            }

            Section("Vocabulary") {
                ForEach(settings.vocabulary, id: \.self) { w in
                    HStack { Text(w); Spacer(); Button { settings.vocabulary.removeAll { $0 == w } } label: { Image(systemName: "minus.circle") }.buttonStyle(.plain) }
                }
                HStack {
                    TextField("Add a word", text: $newWord)
                    Button("Add") { if !newWord.isEmpty { settings.vocabulary.append(newWord); newWord = "" } }
                }
            }

            Section("Replacements") {
                ForEach(settings.replacements) { r in
                    HStack {
                        Text("\(r.from) → \(r.to)")
                        Spacer()
                        Button { settings.replacements.removeAll { $0.id == r.id } } label: { Image(systemName: "minus.circle") }.buttonStyle(.plain)
                    }
                }
                HStack {
                    TextField("When I say", text: $from)
                    TextField("write", text: $to)
                    Button("Add") { if !from.isEmpty && !to.isEmpty { settings.replacements.append(Replacement(from: from, to: to)); from = ""; to = "" } }
                }
            }
        }
        .formStyle(.grouped)
        .padding(.vertical, 8)
    }
}
