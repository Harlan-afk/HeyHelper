import Foundation

/// Splits the brain's streamed reply into sentences to speak right away, and phone commands
/// written in [square brackets] to carry out.
struct ReplyParser {
    struct Output {
        var sentences: [String] = []
        var actions: [PhoneAction] = []
    }

    private(set) var raw = ""
    private(set) var visible = ""
    private var sentence = ""
    private var bracket: String?
    private var sawSentenceEnd = false

    mutating func feed(_ piece: String) -> Output {
        var out = Output()
        raw += piece
        for character in piece {
            if var inside = bracket {
                if character == "]" {
                    if let action = PhoneAction.parse(inside) { out.actions.append(action) }
                    bracket = nil
                } else {
                    inside.append(character)
                    bracket = inside.count > 240 ? nil : inside
                }
                continue
            }
            if character == "[" {
                bracket = ""
                continue
            }

            if sawSentenceEnd {
                sawSentenceEnd = false
                if character.isWhitespace {
                    emitSentence(into: &out)
                }
            }
            visible.append(character)
            sentence.append(character)

            if character.isNewline {
                emitSentence(into: &out)
            } else if ".!?".contains(character) {
                sawSentenceEnd = true
            } else if character == ",", sentence.count > 80 {
                emitSentence(into: &out)
            }
        }
        return out
    }

    mutating func finish() -> Output {
        var out = Output()
        if let inside = bracket, let action = PhoneAction.parse(inside) {
            out.actions.append(action)
        }
        bracket = nil
        emitSentence(into: &out)
        visible = visible.trimmingCharacters(in: .whitespacesAndNewlines)
        return out
    }

    private mutating func emitSentence(into out: inout Output) {
        let text = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        sentence = ""
        if text.contains(where: { $0.isLetter || $0.isNumber }) {
            out.sentences.append(text)
        }
    }
}
