import AppKit
import ApplicationServices
import SwiftUI
import SayWhatKit

@main
struct SayWhatMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var settings = SettingsStore.shared
    @StateObject private var engine = DictationEngine.shared
    @StateObject private var history = HistoryStore.shared

    var body: some Scene {
        MenuBarExtra {
            MenuView()
                .environmentObject(settings)
                .environmentObject(engine)
                .environmentObject(history)
        } label: {
            Image(systemName: engine.phase == .recording ? "waveform.circle.fill" : "quote.bubble")
        }
        .menuBarExtraStyle(.window)

        Settings {
            MacSettingsView()
                .environmentObject(settings)
                .environmentObject(engine)
                .frame(width: 520)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let controller = MacDictationController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        controller.start()
    }
}

/// Hold the hotkey → talk → release → text is pasted into the frontmost app.
/// Quick tap (< 0.3 s) = hands-free mode: tap again to finish.
@MainActor
final class MacDictationController {
    private let engine = DictationEngine.shared
    private let settings = SettingsStore.shared
    private let hud = HUDController()
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var keyDownAt: Date?
    private var handsFree = false
    private var escMonitor: Any?

    func start() {
        Task {
            _ = await AudioRecorder.requestPermission()
            await engine.prepareModel()
        }
        Accessibility.prompt()
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] e in
            Task { @MainActor in self?.handle(e) }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] e in
            Task { @MainActor in self?.handle(e) }
            return e
        }
        escMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] e in
            if e.keyCode == 53 { Task { @MainActor in self?.cancel() } }
        }
        engine.levelSink = { [weak self] l in self?.hud.level = l }
    }

    private func isDown(_ e: NSEvent) -> Bool {
        let f = e.modifierFlags
        switch settings.macHotkey {
        case .rightOption: return f.contains(.option)
        case .rightCommand: return f.contains(.command)
        case .rightControl: return f.contains(.control)
        case .fn: return f.contains(.function)
        }
    }

    private func handle(_ e: NSEvent) {
        guard e.keyCode == settings.macHotkey.keyCode else { return }
        if isDown(e) {
            guard keyDownAt == nil else { return }
            keyDownAt = Date()
            if handsFree { finish(); return }
            if engine.phase == .idle { begin() }
        } else {
            guard let down = keyDownAt else { return }
            keyDownAt = nil
            if engine.phase != .recording { return }
            if Date().timeIntervalSince(down) < 0.3 && !handsFree {
                handsFree = true
                hud.handsFree = true
            } else if !handsFree {
                finish()
            }
        }
    }

    func begin() {
        handsFree = false
        hud.handsFree = false
        engine.start(warm: false)
        if engine.phase == .recording {
            hud.show(.listening)
            NSSound(named: "Pop")?.play()
        }
    }

    func finish() {
        handsFree = false
        guard engine.phase == .recording else { return }
        hud.show(.working)
        Task {
            let text = await engine.stop()
            hud.hide()
            if !text.isEmpty { Paster.paste(text) }
            else if let err = engine.errorMessage { hud.flash(err) }
        }
    }

    func cancel() {
        guard engine.phase == .recording else { return }
        handsFree = false
        engine.cancel()
        hud.hide()
    }
}

enum Accessibility {
    static var trusted: Bool { AXIsProcessTrusted() }
    static func prompt() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
    }
}

enum Paster {
    /// Puts text on the clipboard, sends ⌘V to the frontmost app, then restores the previous clipboard.
    static func paste(_ text: String) {
        let pb = NSPasteboard.general
        let previous = pb.string(forType: .string)
        pb.clearContents()
        pb.setString(text, forType: .string)
        guard Accessibility.trusted else { return }   // no permission: text stays on the clipboard
        let src = CGEventSource(stateID: .combinedSessionState)
        let down = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: true)
        let up = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            guard let previous, !SettingsStore.shared.autoCopy else { return }
            pb.clearContents()
            pb.setString(previous, forType: .string)
        }
    }
}
