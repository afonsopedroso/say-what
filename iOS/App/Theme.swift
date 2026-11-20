import SwiftUI
import SayWhatKit

enum Theme {
    /// Say What red-orange — loud, like the name.
    static let accent = Color(red: 1.0, green: 0.30, blue: 0.20)
    static let accentDeep = Color(red: 0.86, green: 0.18, blue: 0.10)
    static let ink = Color(red: 0.06, green: 0.06, blue: 0.07)
    static let card = Color(uiColor: .secondarySystemBackground)
    static let display = Font.system(size: 34, weight: .heavy, design: .rounded)
}

/// The big round talk button with a live level ring — used in the app and mirrored in the keyboard.
struct MicButton: View {
    var phase: DictationEngine.Phase
    var level: Float
    var size: CGFloat = 148
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(Theme.accent.opacity(0.18))
                    .scaleEffect(phase == .recording ? 1.0 + CGFloat(level) * 0.45 : 1.0)
                    .animation(.easeOut(duration: 0.12), value: level)
                Circle()
                    .fill(LinearGradient(colors: [Theme.accent, Theme.accentDeep], startPoint: .top, endPoint: .bottom))
                    .frame(width: size * 0.72, height: size * 0.72)
                    .shadow(color: Theme.accent.opacity(0.45), radius: 18, y: 8)
                Group {
                    switch phase {
                    case .idle:
                        Image(systemName: "mic.fill")
                    case .recording:
                        RoundedRectangle(cornerRadius: 6).frame(width: size * 0.2, height: size * 0.2)
                    case .transcribing, .polishing:
                        ProgressView().tint(.white).scaleEffect(1.6)
                    }
                }
                .font(.system(size: size * 0.26, weight: .bold))
                .foregroundStyle(.white)
            }
            .frame(width: size, height: size)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(phase == .recording ? "Stop dictation" : "Start dictation")
    }
}

struct LangChip: View {
    @ObservedObject var settings = SettingsStore.shared
    var body: some View {
        Button {
            settings.language = settings.language.next
        } label: {
            Text(settings.language.short)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(Capsule().fill(Theme.accent.opacity(0.14)))
                .foregroundStyle(Theme.accent)
        }
        .accessibilityLabel("Language: \(settings.language.label). Tap to change.")
    }
}

