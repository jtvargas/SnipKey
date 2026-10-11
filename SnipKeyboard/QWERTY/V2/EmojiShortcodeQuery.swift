import Foundation

/// The literal colon token immediately before the caret, not an earlier token in the field.
struct EmojiShortcodeQuery: Equatable, Sendable {
    let triggerText: String
    let query: String
    private let isClosed: Bool

    static func parse(_ context: String) -> EmojiShortcodeQuery? {
        guard !context.isEmpty else { return nil }
        let end = context.endIndex
        let last = context.index(before: end)
        let isClosed = context[last] == ":"
        var start = isClosed ? last : end
        while start > context.startIndex {
            let previous = context.index(before: start)
            guard isShortcodeCharacter(context[previous]) else { break }
            start = previous
        }
        if start > context.startIndex {
            let colon = context.index(before: start)
            if context[colon] == ":", (!isClosed || start < last),
               hasOpeningBoundary(in: context, at: colon) {
                let queryEnd = isClosed ? last : end
                return EmojiShortcodeQuery(triggerText: String(context[colon...]),
                    query: context[start..<queryEnd].lowercased(), isClosed: isClosed)
            }
        }
        // A lone colon is an explicit browse request, but never the second colon in ::.
        if isClosed, hasOpeningBoundary(in: context, at: last) {
            return EmojiShortcodeQuery(triggerText: ":", query: "", isClosed: false)
        }
        return nil
    }

    /// Open tokens must not consume only the left half of a shortcode. A closing
    /// colon makes the token complete; following text then belongs to the host.
    func canReplace(contextAfterInput: String?) -> Bool {
        guard !isClosed, let next = contextAfterInput?.first else { return true }
        return next != ":" && !Self.isShortcodeCharacter(next)
    }

    private static func isShortcodeCharacter(_ character: Character) -> Bool {
        guard character.unicodeScalars.count == 1,
              let scalar = character.unicodeScalars.first else { return false }
        switch scalar.value {
        case 65...90, 97...122, 48...57, 95, 45, 43: return true
        default: return false
        }
    }

    private static func hasOpeningBoundary(in context: String, at colon: String.Index) -> Bool {
        guard colon > context.startIndex else { return true }
        let previous = context[context.index(before: colon)]
        if previous.isWhitespace { return true }
        if previous == "\"" || previous == "'" || previous == "<" { return true }
        guard previous.unicodeScalars.count == 1,
              let scalar = previous.unicodeScalars.first else { return false }
        return scalar.properties.generalCategory == .openPunctuation
            || scalar.properties.generalCategory == .initialPunctuation
    }
}
