import SwiftUI
import SayWhatKit

struct DictateView: View {
    @EnvironmentObject var engine: DictationEngine
    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject var session: KeyboardSession
    @EnvironmentObject var history: HistoryStore
    @State private var text = ""
    @State private var copied = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    header
                    MicButton(phase: engine.phase, level: engine.level, size: 172) { toggle() }
                        .padding(.top, 4)
                    Text(statusLine)
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .foregroundStyle(engine.phase == .recording ? Theme.accent : .secondary)
                        .animation(.default, value: engine.phase)
                    if let err = engine.errorMessage {
                        Label(err, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote).foregroundStyle(.orange)
                            .multilineTextAlignment(.center)
                    }
                    resultCard
                    sessionCard
                    statsRow
                }
                .padding(20)
            }
            .navigationTitle("Say What")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { LangChip() } }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            if settings.engine == .local && !engine.modelReady {
                HStack {
                    ProgressView(value: engine.modelProgress).tint(Theme.accent)
                    Text(engine.modelState).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var statusLine: String {
        switch engine.phase {
        case .idle: return "Tap and talk — English or Português"
        case .recording: return "Listening… tap to finish"
        case .transcribing: return "Transcribing…"
        case .polishing: return "Polishing…"
        }
    }

    @ViewBuilder private var resultCard: some View {
        if !text.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                TextEditor(text: $text)
                    .font(.body)
                    .frame(minHeight: 110)
                    .scrollContentBackground(.hidden)
                HStack(spacing: 10) {
                    Button { copy() } label: {
                        Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                    }.buttonStyle(.borderedProminent)
                    ShareLink(item: text) { Label("Share", systemImage: "square.and.arrow.up") }
                        .buttonStyle(.bordered)
                    Spacer()
                    Button(role: .destructive) { text = "" } label: { Image(systemName: "xmark") }
                        .buttonStyle(.bordered)
                }
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 20).fill(Theme.card))
        }
    }

    private var sessionCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "keyboard.fill").foregroundStyle(Theme.accent)
                Text("Keyboard session").font(.headline)
                Spacer()
                Toggle("", isOn: Binding(get: { session.active },
                                         set: { $0 ? session.begin(recordNow: false) : session.end() }))
                    .labelsHidden()
            }
            Text(session.active
                 ? "Live — the Say What keyboard can dictate instantly in any app\(session.endsAt.map { " until \($0.formatted(date: .omitted, time: .shortened))" } ?? "")."
                 : "Starts automatically when you tap the mic on the Say What keyboard.")
                .font(.footnote).foregroundStyle(.secondary)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 20).fill(Theme.card))
    }

    private var statsRow: some View {
        HStack {
            stat("\(history.totalWords)", "words dictated")
            Divider().frame(height: 34)
            stat("\(history.minutesSaved)", "min saved")
            Divider().frame(height: 34)
            stat("\(history.items.count)", "dictations")
        }
        .padding(.vertical, 6)
    }

    private func stat(_ v: String, _ l: String) -> some View {
        VStack(spacing: 2) {
            Text(v).font(.system(.title3, design: .rounded).weight(.heavy))
            Text(l).font(.caption2).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity)
    }

    private func toggle() {
        haptic()
        switch engine.phase {
        case .idle:
            engine.start()
        case .recording:
            Task {
                let t = await engine.stop()
                if !t.isEmpty {
                    text = t
                    if settings.autoCopy { copy() }
                }
                haptic()
            }
        default: break
        }
    }

    private func copy() {
        UIPasteboard.general.string = text
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
    }

    private func haptic() {
        if settings.haptics { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
    }
}

/// Shown when the keyboard opened the app to start a session.
struct HandoffView: View {
    @EnvironmentObject var engine: DictationEngine
    @EnvironmentObject var session: KeyboardSession

    var body: some View {
        ZStack {
            Theme.ink.ignoresSafeArea()
            VStack(spacing: 26) {
                HStack {
                    Image(systemName: "arrow.backward")
                    Text("Swipe back to your app").bold()
                }
                .font(.title3)
                .foregroundStyle(.white)
                .padding(.top, 30)
                Text("Tap ◀ at the top-left, or swipe right along the bottom edge. Keep talking — Say What is listening and will type into your text field.")
                    .font(.callout).foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center).padding(.horizontal, 30)
                Spacer()
                MicButton(phase: engine.phase, level: engine.level, size: 190) {
                    if engine.phase == .recording { Bridge.post(Bridge.Note.stop) }
                }
                Text(engine.phase == .recording ? "Listening…" : "Session is live")
                    .font(.headline).foregroundStyle(Theme.accent)
                Spacer()
                Button("Done") { session.showHandoff = false }
                    .buttonStyle(.bordered).tint(.white)
                    .padding(.bottom, 30)
            }
        }
    }
}
