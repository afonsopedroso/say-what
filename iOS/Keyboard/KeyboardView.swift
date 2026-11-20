import SwiftUI
import SayWhatKit

private let accent = Color(red: 1.0, green: 0.30, blue: 0.20)
private let accentDeep = Color(red: 0.86, green: 0.18, blue: 0.10)

struct KeyboardView: View {
    @ObservedObject var model: KeyboardModel

    var body: some View {
        VStack(spacing: 8) {
            topBar
            HStack(spacing: 8) {
                VStack(spacing: 8) {
                    KeyCap(label: ",") { model.type(",") }
                    KeyCap(label: ".") { model.type(".") }
                    KeyCap(label: "?") { model.type("?") }
                }
                .frame(width: 58)
                micArea
                    .frame(maxWidth: .infinity)
                VStack(spacing: 8) {
                    RepeatKey(systemImage: "delete.left", onTap: model.deleteBackward, onRepeat: model.deleteWord)
                    KeyCap(systemImage: "arrow.uturn.backward", disabled: model.lastInserted == nil) { model.undoLast() }
                    KeyCap(label: "!") { model.type("!") }
                }
                .frame(width: 58)
            }
            HStack(spacing: 8) {
                if model.needsGlobe {
                    KeyCap(systemImage: "globe") { model.nextKeyboard() }.frame(width: 50)
                }
                KeyCap(label: model.language.short, tint: accent) { model.cycleLanguage() }.frame(width: 58)
                KeyCap(label: "space") { model.type(" ") }
                KeyCap(label: model.returnTitle, prominent: true) { model.type("\n") }.frame(width: 92)
            }
            .frame(height: 44)
        }
        .padding(.horizontal, 6)
        .padding(.top, 6)
        .padding(.bottom, 4)
    }

    private var topBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "quote.bubble.fill").foregroundStyle(accent)
            Text(statusText)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(model.message != nil ? Color.orange : .secondary)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
            Spacer()
            if model.state == .recording {
                Button("Cancel") { model.cancelTapped() }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(height: 30)
        .padding(.horizontal, 4)
    }

    private var statusText: String {
        if let m = model.message { return m }
        switch model.state {
        case .off: return "Tap the mic — Say What opens, then swipe back"
        case .idle: return "Tap to talk · \(model.language.label)"
        case .recording: return "Listening… tap to insert"
        case .transcribing: return "Writing it out…"
        }
    }

    private var micArea: some View {
        Button(action: model.micTapped) {
            ZStack {
                RoundedRectangle(cornerRadius: 22)
                    .fill(accent.opacity(model.state == .recording ? 0.22 : 0.12))
                Circle()
                    .fill(accent.opacity(0.25))
                    .frame(width: 92, height: 92)
                    .scaleEffect(model.state == .recording ? 1 + CGFloat(model.level) * 0.5 : 1)
                    .animation(.easeOut(duration: 0.12), value: model.level)
                Circle()
                    .fill(LinearGradient(colors: [accent, accentDeep], startPoint: .top, endPoint: .bottom))
                    .frame(width: 76, height: 76)
                    .shadow(color: accent.opacity(0.4), radius: 10, y: 4)
                Group {
                    switch model.state {
                    case .recording:
                        RoundedRectangle(cornerRadius: 5).frame(width: 22, height: 22)
                    case .transcribing:
                        ProgressView().tint(.white)
                    default:
                        Image(systemName: "mic.fill").font(.system(size: 30, weight: .bold))
                    }
                }
                .foregroundStyle(.white)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(model.state == .recording ? "Stop and insert" : "Dictate")
    }
}

struct KeyCap: View {
    var label: String? = nil
    var systemImage: String? = nil
    var tint: Color? = nil
    var prominent = false
    var disabled = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                if let systemImage { Image(systemName: systemImage).font(.system(size: 17, weight: .medium)) }
                else { Text(label ?? "").font(.system(size: label?.count == 1 ? 22 : 15, weight: label?.count == 1 ? .regular : .semibold)) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .foregroundStyle(prominent ? .white : (tint ?? .primary))
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(prominent ? accent : Color(uiColor: .systemBackground).opacity(0.9))
                    .shadow(color: .black.opacity(0.18), radius: 0, y: 1)
            )
            .opacity(disabled ? 0.4 : 1)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }
}

/// Delete key: tap deletes one character, holding repeats (by words after a moment).
struct RepeatKey: View {
    var systemImage: String
    var onTap: () -> Void
    var onRepeat: () -> Void
    @State private var timer: Timer?
    @State private var pressed = false

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 17, weight: .medium))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: 8)
                .fill(pressed ? Color.gray.opacity(0.35) : Color(uiColor: .systemBackground).opacity(0.9))
                .shadow(color: .black.opacity(0.18), radius: 0, y: 1))
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard !pressed else { return }
                        pressed = true
                        onTap()
                        var ticks = 0
                        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
                            ticks += 1
                            if ticks > 4 { ticks > 14 ? onRepeat() : onTap() }
                        }
                    }
                    .onEnded { _ in
                        pressed = false
                        timer?.invalidate(); timer = nil
                    }
            )
            .accessibilityLabel("Delete")
            .accessibilityAddTraits(.isButton)
    }
}
