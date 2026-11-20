import XCTest
@testable import SayWhatKit

final class TextCleanerTests: XCTestCase {
    func c(_ s: String, _ o: TextCleaner.Options = .init()) -> String { TextCleaner.clean(s, options: o) }

    func testFillersEnglish() {
        XCTAssertEqual(c("Um, so I think, uh, we should go."), "So I think, we should go.")
        XCTAssertEqual(c("I I think that's fine"), "I think that's fine")
    }

    func testFillersPortuguese() {
        XCTAssertEqual(c("Hã, eu acho que, hum, vamos amanhã."), "Eu acho que, vamos amanhã.")
        XCTAssertEqual(c("Tipo, está tudo bem."), "Está tudo bem.")
    }

    func testVoiceCommands() {
        XCTAssertEqual(c("Hello there new line how are you"), "Hello there\nHow are you")
        XCTAssertEqual(c("Olá nova linha tudo bem ponto de interrogação"), "Olá\nTudo bem?")
        XCTAssertEqual(c("Meet at 5. Meet at 6. Scratch that. Meet at 7."), "Meet at 5. Meet at 7.")
        XCTAssertEqual(c("Primeiro parágrafo. Novo parágrafo. Segundo."), "Primeiro parágrafo.\n\nSegundo.")
    }

    func testHallucinations() {
        XCTAssertEqual(c("Thank you."), "")
        XCTAssertEqual(c("Obrigado."), "")
        XCTAssertEqual(c("[Music]"), "")
    }

    func testReplacementsAndSnippets() {
        var o = TextCleaner.Options()
        o.replacements = [Replacement(from: "chat gpt", to: "ChatGPT")]
        o.snippets = [Snippet(trigger: "my email", text: "afonso@example.com")]
        XCTAssertEqual(c("ask chat gpt and send it to my email.", o), "Ask ChatGPT and send it to afonso@example.com")
    }

    func testStyles() {
        var o = TextCleaner.Options(); o.style = .casual
        XCTAssertEqual(c("Sounds good, see you later.", o), "sounds good, see you later")
        XCTAssertEqual(c("I will be there.", o), "I will be there")
        o.style = .formal
        XCTAssertEqual(c("thanks for the update", o), "Thanks for the update.")
    }

    func testPunctuationTidy() {
        XCTAssertEqual(c("hello , world .how are you"), "Hello, world. How are you")
        XCTAssertEqual(c("i'm here and i think so"), "I'm here and I think so")
        XCTAssertEqual(c("visit example.com today"), "Visit example.com today")
    }

    func testFit() {
        XCTAssertEqual(TextCleaner.fit("Hello there.", after: "I said"), " hello there.")
        XCTAssertEqual(TextCleaner.fit("Hello there.", after: "Done. "), "Hello there.")
        XCTAssertEqual(TextCleaner.fit("Hello there.", after: ""), "Hello there.")
        XCTAssertEqual(TextCleaner.fit("I think so.", after: "well"), " I think so.")
        XCTAssertEqual(TextCleaner.fit("NASA rocks", after: "well"), " NASA rocks")
        XCTAssertEqual(TextCleaner.fit("Olá.", after: "Linha\n"), "Olá.")
    }
}
