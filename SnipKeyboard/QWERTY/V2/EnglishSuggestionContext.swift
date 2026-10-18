import Foundation

/// The exact input used by a background prediction. Callers may bound context before
/// scheduling, but must validate the whole supplied context, not only partialWord.
/// An empty partialWord is valid after whitespace and implies replacementLength == 0.
struct PredictiveTextSnapshot: Equatable, Sendable {
    let contextBeforeInput: String?
    let partialWord: String
}

/// Tokenization shared by English ranking and the existing system-language fallback.
/// Apostrophes inside/trailing a word stay in its replacement span; opening quotes do not.
struct EnglishSuggestionContext: Sendable {
    let partialWord: String
    let previousWord: String?
    let allowsNextWord: Bool
    let startsSentence: Bool
    private let usesAllCaps: Bool
    private let usesCurlyApostrophe: Bool

    init(_ context: String) {
        let end = context.endIndex
        var wordStart = end
        while wordStart > context.startIndex {
            let before = context.index(before: wordStart)
            let character = context[before]
            guard character.isLetter || character.isNumber || Self.isApostrophe(character) else { break }
            wordStart = before
        }
        while wordStart < end, Self.isApostrophe(context[wordStart]) {
            wordStart = context.index(after: wordStart)
        }
        partialWord = String(context[wordStart..<end])
        allowsNextWord = partialWord.isEmpty && context.last?.isWhitespace == true
        var letterCount = 0
        var allUppercase = true
        for character in partialWord where character.isLetter {
            letterCount += 1
            if !character.isUppercase { allUppercase = false }
        }
        usesAllCaps = letterCount > 1 && allUppercase
        usesCurlyApostrophe = partialWord.contains("’")

        var cursor = wordStart
        var sentenceBoundary = false
        while cursor > context.startIndex {
            let before = context.index(before: cursor)
            let character = context[before]
            if character.isLetter || character.isNumber { break }
            if character == "." || character == "!" || character == "?" || character.isNewline {
                sentenceBoundary = true
                break
            }
            cursor = before
        }
        startsSentence = sentenceBoundary || cursor == context.startIndex
        guard !startsSentence else {
            previousWord = nil
            return
        }
        let previousEnd = cursor
        while cursor > context.startIndex {
            let before = context.index(before: cursor)
            let character = context[before]
            guard character.isLetter || Self.isApostrophe(character) else { break }
            cursor = before
        }
        while cursor < previousEnd, Self.isApostrophe(context[cursor]) {
            cursor = context.index(after: cursor)
        }
        previousWord = cursor < previousEnd ? String(context[cursor..<previousEnd]) : nil
    }

    static func isApostrophe(_ character: Character) -> Bool {
        character == "'" || character == "’"
    }

    static func normalized(_ text: String) -> String {
        text.lowercased().replacingOccurrences(of: "’", with: "'")
    }

    /// Keep canonical I/contractions and supplementary-lexicon proper-name casing.
    /// One uppercase initial is title case, not caps lock; two or more are all caps.
    func matchCasing(_ word: String) -> String {
        var result = word
        if usesAllCaps {
            result = result.uppercased()
        } else if partialWord.first?.isUppercase == true || (partialWord.isEmpty && startsSentence) {
            result = result.prefix(1).uppercased() + result.dropFirst()
        }
        if usesCurlyApostrophe {
            result = result.replacingOccurrences(of: "'", with: "’")
        }
        return result
    }
}
