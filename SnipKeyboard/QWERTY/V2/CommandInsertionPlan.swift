import Foundation

/// A single host edit. A selection is replaced by insertText, never by backward deletion.
struct CommandInsertionPlan: Equatable {
    let deleteCount: Int
    let text: String

    static func make(command: String, contextBeforeInput: String?, contextAfterInput: String?, hasSelection: Bool) -> Self {
        let before = contextBeforeInput ?? ""
        let atTokenEnd = contextAfterInput?.first.map { $0.isWhitespace } ?? true
        if !hasSelection, atTokenEnd,
           let slash = before.lastIndex(of: "/"),
           slash == before.startIndex || before[before.index(before: slash)].isWhitespace {
            let query = before[before.index(after: slash)...]
            // Only the live trigger/query, never a command's arguments or earlier prose.
            if query.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" }) {
                return Self(deleteCount: before[slash...].count, text: command)
            }
        }
        let separator = before.last.map { $0.isWhitespace ? "" : " " } ?? ""
        return Self(deleteCount: 0, text: separator + command)
    }
}

/// Keeps trigger matching anchored to the original string (including Unicode source spans).
/// Explicit slash commands require whitespace on both sides of the trigger word.
enum CommandSource {
    static func suffix(in context: String, trigger: String) -> String? {
        guard let range = context.range(of: trigger, options: [.backwards, .caseInsensitive]),
              range.lowerBound == context.startIndex || context[context.index(before: range.lowerBound)].isWhitespace,
              range.upperBound == context.endIndex || context[range.upperBound].isWhitespace else { return nil }
        let suffix = context[range.lowerBound...]
        // A newline or subsequent command ends this command's editable source span.
        guard !suffix.contains(where: { $0.isNewline }),
              !suffix.split(whereSeparator: \.isWhitespace).dropFirst().contains(where: { $0.hasPrefix("/") }) else { return nil }
        return String(suffix)
    }
}
