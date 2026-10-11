import Foundation

/// Search owns its text and caret. No textDocumentProxy or host action is reachable
/// from these edits; the native keyboard's space-drag can still move the local caret.
struct EmojiSearchQuery {
    private(set) var text = ""
    private(set) var caret = 0

    var contextBeforeInput: String { String(text.prefix(caret)) }

    mutating func insert(_ value: String) {
        if caret == text.count {
            text.append(value)
            caret = text.count
            return
        }
        let index = text.index(text.startIndex, offsetBy: caret)
        // Count the joined prefix, not its operands separately: a combining mark
        // can merge with the previous grapheme instead of advancing the caret.
        let prefix = String(text[..<index]) + value
        text.insert(contentsOf: value, at: index)
        caret = min(prefix.count, text.count)
    }

    mutating func deleteBackward() {
        guard caret > 0 else { return }
        let index = text.index(text.startIndex, offsetBy: caret - 1)
        text.remove(at: index)
        caret = min(caret - 1, text.count)
    }

    mutating func moveCaret(by offset: Int) {
        setCaret(to: caret + offset)
    }

    mutating func setCaret(to position: Int) {
        caret = min(max(0, position), text.count)
    }

    mutating func clear() {
        text.removeAll(keepingCapacity: true)
        caret = 0
    }
}
