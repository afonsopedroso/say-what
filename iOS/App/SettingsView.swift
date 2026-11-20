import SwiftUI
import SayWhatKit

struct SettingsView: View {
    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject var engine: DictationEngine
    @EnvironmentObject var session: KeyboardSession
    @State private var key = SettingsStore.shared.groqKey

    var body: some View {
        NavigationStack {
            Form {
                Section("Language") {
                    Picker("Dictation language", selection: $settings.language) {
                        ForEach(DictationLanguage.allCases) { Text($0.label).tag($0) }
                    }
                    Text("Auto picks English or European Portuguese per dictation — nothing else, so it never drifts into Spanish or Brazilian.")
                        .font(.footnote).foregroundStyle(.secondary)
                }

                Section("Speech recognition") {
                    Picker("Engine", selection: $settings.engine) {
                        ForEach(TranscriptionEngine.allCases) { Text($0.label).tag($0) }
                    }
                    .onChange(of: settings.engine) { _, _ in Task { await engine.prepareModel() } }
                    if settings.engine == .local {
                        ForEach(LocalModel.all) { m in
                            Button {
                                settings.localModel = m.id
                                Task { await engine.prepareModel() }
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("\(m.name) · \(m.size)").foregroundStyle(.primary)
                                        Text(m.note).font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if settings.localModel == m.id { Image(systemName: "checkmark").foregroundStyle(Theme.accent) }
                                }
                            }
                        }
                        HStack {
                            Text(engine.modelState).font(.footnote).foregroundStyle(.secondary)
                            Spacer()
                            if !engine.modelReady && engine.modelProgress > 0 && engine.modelProgress < 1 {
                                Text("\(Int(engine.modelProgress * 100))%").font(.footnote.monospacedDigit())
                            }
                        }
                    }
                }

                Section {
                    Picker("AI polish", selection: $settings.polish) {
                        ForEach(PolishMode.allCases) { Text($0.label).tag($0) }
                    }
                    if settings.polish == .apple && !Polisher.appleAvailable {
                        Text("Apple Intelligence isn't available on this iPhone, so Say What uses the instant rules instead.")
                            .font(.footnote).foregroundStyle(.orange)
                    }
                    Picker("Style", selection: $settings.style) {
                        ForEach(WritingStyle.allCases) { Text($0.label).tag($0) }
                    }
                    Toggle("Remove filler words (um, uh, hã, tipo…)", isOn: $settings.removeFillers)
                    Toggle("Voice commands", isOn: $settings.voiceCommands)
                } header: { Text("Clean-up") } footer: {
                    Text("Voice commands: “new line / nova linha”, “new paragraph / novo parágrafo”, “full stop / ponto final”, “comma / vírgula”, “question mark / ponto de interrogação”, “scratch that / apaga isso”.")
                }

                Section {
                    SecureField("gsk_…", text: $key)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .onChange(of: key) { _, v in settings.groqKey = v }
                    TextField("LLM model", text: $settings.groqLLMModel)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                } header: { Text("Groq (optional)") } footer: {
                    Text("Only used if you pick Groq above. Stored in the iPhone Keychain. Get a key at console.groq.com.")
                }

                Section {
                    Picker("Keep session alive", selection: $settings.sessionMinutes) {
                        Text("5 minutes").tag(5); Text("15 minutes").tag(15); Text("1 hour").tag(60); Text("4 hours").tag(240)
                    }
                    Toggle("Haptics", isOn: $settings.haptics)
                    Toggle("Auto-copy in app", isOn: $settings.autoCopy)
                    Button("Set up the Say What keyboard") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    }
                } header: { Text("Keyboard") } footer: {
                    Text("Settings › Say What › Keyboards › turn on Say What and Allow Full Access (needed to talk to this app — nothing you type is collected). While a session is live the mic indicator stays on; it ends automatically after the time above.")
                }

                Section {
                    Button("Show welcome again") { settings.onboarded = false }
                    LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")
                }
            }
            .navigationTitle("Settings")
        }
    }
}

struct OnboardingView: View {
    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject var engine: DictationEngine
    @State private var step = 0
    @State private var micGranted = false

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $step) {
                page(icon: "quote.bubble.fill", title: "Say What",
                     body: "Talk instead of type — in English or European Portuguese. Say What writes it cleanly: punctuation, no “ums”, your words.") {
                    Button("Get started") { step = 1 }.buttonStyle(.borderedProminent)
                }.tag(0)

                page(icon: "mic.fill", title: "Your microphone",
                     body: "Speech is processed on this iPhone by default. Nothing leaves the device unless you switch on Groq.") {
                    Button(micGranted ? "Microphone allowed ✓" : "Allow microphone") {
                        Task {
                            micGranted = await AudioRecorder.requestPermission()
                            if micGranted { step = 2 }
                        }
                    }.buttonStyle(.borderedProminent)
                }.tag(1)

                page(icon: "arrow.down.circle.fill", title: "Download the voice model",
                     body: "\(LocalModel.named(settings.localModel).name) (\(LocalModel.named(settings.localModel).size)) — a one-time download, then it works offline. Use Wi-Fi.") {
                    VStack(spacing: 12) {
                        if engine.modelReady {
                            Label("Ready", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                            Button("Next") { step = 3 }.buttonStyle(.borderedProminent)
                        } else {
                            ProgressView(value: engine.modelProgress).tint(Theme.accent).frame(width: 220)
                            Text(engine.modelState).font(.caption).foregroundStyle(.secondary)
                            Button("Download") { Task { await engine.prepareModel() } }.buttonStyle(.borderedProminent)
                            Button("Skip — I'll do it later") { step = 3 }.font(.footnote)
                        }
                    }
                }.tag(2)

                page(icon: "keyboard.fill", title: "Add the keyboard",
                     body: "Settings › Say What › Keyboards → turn on Say What and Allow Full Access. Then in any app, tap 🌐 to switch to Say What and hit the mic.") {
                    VStack(spacing: 12) {
                        Button("Open Settings") {
                            if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                        }.buttonStyle(.borderedProminent)
                        Button("Done") { settings.onboarded = true }
                    }
                }.tag(3)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))
        }
        .background(Color(uiColor: .systemBackground))
    }

    private func page<C: View>(icon: String, title: String, body: String, @ViewBuilder cta: () -> C) -> some View {
        VStack(spacing: 22) {
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 64, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 128, height: 128)
                .background(RoundedRectangle(cornerRadius: 32).fill(Theme.accent))
            Text(title).font(Theme.display)
            Text(body).multilineTextAlignment(.center).foregroundStyle(.secondary).padding(.horizontal, 32)
            cta()
            Spacer()
            Spacer()
        }
    }
}
