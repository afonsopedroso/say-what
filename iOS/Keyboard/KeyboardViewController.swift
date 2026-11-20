import SwiftUI
import UIKit
import SayWhatKit

final class KeyboardViewController: UIInputViewController {
    private var model: KeyboardModel!
    private var host: UIHostingController<KeyboardView>!

    override func viewDidLoad() {
        super.viewDidLoad()
        model = KeyboardModel(controller: self)
        host = UIHostingController(rootView: KeyboardView(model: model))
        host.view.backgroundColor = .clear
        host.view.translatesAutoresizingMaskIntoConstraints = false
        addChild(host)
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            host.view.heightAnchor.constraint(equalToConstant: 268),
        ])
        host.didMove(toParent: self)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        model.appear()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        model.disappear()
    }

    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        model.returnTitle = returnTitle()
    }

    private func returnTitle() -> String {
        switch textDocumentProxy.returnKeyType {
        case .go: return "Go"
        case .search, .google, .yahoo: return "Search"
        case .send: return "Send"
        case .done: return "Done"
        case .next: return "Next"
        case .join: return "Join"
        default: return "return"
        }
    }

    /// Keyboards can't call UIApplication.shared, but the responder chain still reaches the host app's UIApplication.
    func openContainingApp(_ url: URL) {
        var responder: UIResponder? = self
        while let r = responder {
            if let app = r as? UIApplication {
                app.open(url, options: [:], completionHandler: nil)
                return
            }
            responder = r.next
        }
        extensionContext?.open(url, completionHandler: nil)
    }
}

@MainActor
final class KeyboardModel: ObservableObject {
    @Published var state: Bridge.SessionState = .off
    @Published var level: Float = 0
    @Published var message: String?
    @Published var language: DictationLanguage = .auto
    @Published var returnTitle = "return"
    @Published var lastInserted: String?

    weak var controller: KeyboardViewController?
    private let observer = DarwinObserver()
    private var poll: Timer?
    private var lastResultID: String?
    private var waitingToOpen = false

    init(controller: KeyboardViewController) {
        self.controller = controller
    }

    var hasFullAccess: Bool { controller?.hasFullAccess ?? false }
    var needsGlobe: Bool { controller?.needsInputModeSwitchKey ?? true }

    func appear() {
        lastResultID = Bridge.defaults.string(forKey: Bridge.Key.resultID)
        language = DictationLanguage(rawValue: Bridge.defaults.string(forKey: "language") ?? "") ?? .auto
        observer.observe(Bridge.Note.result) { [weak self] in self?.checkResult() }
        observer.observe(Bridge.Note.state) { [weak self] in self?.refresh() }
        poll = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        refresh()
        if !hasFullAccess { message = "Turn on Allow Full Access: Settings › General › Keyboard › Keyboards › Say What" }
    }

    func disappear() {
        poll?.invalidate(); poll = nil
        observer.removeAll()
    }

    func refresh() {
        let s = Bridge.state
        if s != state { state = s }
        level = s == .recording ? Bridge.defaults.float(forKey: Bridge.Key.level) : 0
        checkResult()
    }

    private func checkResult() {
        let id = Bridge.defaults.string(forKey: Bridge.Key.resultID)
        guard let id, id != lastResultID else { return }
        lastResultID = id
        if let err = Bridge.defaults.string(forKey: Bridge.Key.error), !err.isEmpty {
            message = err
            return
        }
        guard let text = Bridge.defaults.string(forKey: Bridge.Key.resultText), !text.isEmpty else { return }
        insert(text)
    }

    private func insert(_ text: String) {
        guard let proxy = controller?.textDocumentProxy else { return }
        let fitted = TextCleaner.fit(text, after: proxy.documentContextBeforeInput)
        proxy.insertText(fitted)
        lastInserted = fitted
        message = nil
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    // MARK: Actions

    func micTapped() {
        guard hasFullAccess else {
            message = "Allow Full Access first: Settings › General › Keyboard › Keyboards › Say What"
            return
        }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        message = nil
        switch Bridge.state {
        case .off:
            // No live session → open the app; it starts listening immediately.
            controller?.openContainingApp(URL(string: "\(Bridge.urlScheme)://dictate")!)
        case .idle:
            Bridge.post(Bridge.Note.start)
            state = .recording
        case .recording:
            Bridge.post(Bridge.Note.stop)
            state = .transcribing
        case .transcribing:
            break
        }
    }

    func cancelTapped() {
        Bridge.post(Bridge.Note.cancel)
    }

    func cycleLanguage() {
        language = language.next
        Bridge.defaults.set(language.rawValue, forKey: "language")
    }

    func undoLast() {
        guard let last = lastInserted, let proxy = controller?.textDocumentProxy else { return }
        if (proxy.documentContextBeforeInput ?? "").hasSuffix(last) {
            for _ in 0..<last.count { proxy.deleteBackward() }
        }
        lastInserted = nil
    }

    func type(_ s: String) {
        controller?.textDocumentProxy.insertText(s)
        UIDevice.current.playInputClick()
    }

    func deleteBackward() {
        controller?.textDocumentProxy.deleteBackward()
    }

    func deleteWord() {
        guard let proxy = controller?.textDocumentProxy, let before = proxy.documentContextBeforeInput, !before.isEmpty else {
            controller?.textDocumentProxy.deleteBackward(); return
        }
        var count = 0
        var seenLetter = false
        for ch in before.reversed() {
            if ch.isWhitespace || ch.isPunctuation { if seenLetter { break } } else { seenLetter = true }
            count += 1
        }
        for _ in 0..<max(1, count) { proxy.deleteBackward() }
    }

    func nextKeyboard() { controller?.advanceToNextInputMode() }
}
