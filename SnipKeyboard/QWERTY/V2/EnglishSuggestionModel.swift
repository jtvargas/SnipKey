import Foundation

extension SwipeLexicon {
    /// Both consumers first access this on their background queues. Swift's static
    /// initialization serializes the single load; the packed word data is not duplicated.
    static let sharedForSuggestionsAndSwipe = SwipeLexicon.loadBundled()
}

/// A bounded English unigram/bigram ranker, not an autocorrect or neural decoder.
/// All construction and queries run on the predictive engine's serial background queue.
final class EnglishSuggestionModel {
    struct Suggestion {
        let text: String
        let score: Float
        let isCorrection: Bool
        let usesContext: Bool
    }

    private struct Edge {
        let target: Int32
        var score: Float
    }

    private struct RankedWord {
        let id: Int
        let score: Float
        let correction: Bool
    }

    private let lexicon: SwipeLexicon
    private let alphabetical: [Int32]
    private let edges: [Edge]
    private let edgeStart: [Int32]
    private let extraPriors: [Float]
    private static let backoff = Float(log(0.2))

    static func loadBundled() -> EnglishSuggestionModel? {
        guard let lexicon = SwipeLexicon.sharedForSuggestionsAndSwipe,
              let url = Bundle.main.url(forResource: "english-bigrams-en", withExtension: "tsv"),
              let data = try? Data(contentsOf: url)
        else { return nil }
        return EnglishSuggestionModel(lexicon: lexicon, bigrams: data)
    }

    init?(lexicon: SwipeLexicon, bigrams: Data) {
        guard let text = String(data: bigrams, encoding: .ascii),
              text.hasPrefix("# snipkey-english-bigrams-v1\n") else { return nil }
        let wordCount = lexicon.count + 2
        var starts = [Int32](repeating: 0, count: wordCount + 1)
        var totals = [Float](repeating: 0, count: wordCount)
        var loaded: [Edge] = []
        loaded.reserveCapacity(32_768)
        var priors = [Float](repeating: .nan, count: 2)
        var hasLexiconCount = false
        var previousSource = -1
        var previousTarget = -1
        for line in text.split(separator: "\n") {
            if line.first == "#" { continue }
            let fields = line.split(separator: "\t")
            if fields.count == 2, fields[0] == "@lexicon" {
                guard Int(fields[1]) == lexicon.count, !hasLexiconCount else { return nil }
                hasLexiconCount = true
            } else if fields.count == 2, fields[0] == "@a" || fields[0] == "@i" {
                let index = fields[0] == "@a" ? 0 : 1
                guard let prior = Float(fields[1]), prior.isFinite, prior < 0,
                      priors[index].isNaN else { return nil }
                priors[index] = prior
            } else {
                guard fields.count == 3,
                      let source = Int(fields[0]), let target = Int(fields[1]),
                      let count = Float(fields[2]), count.isFinite, count > 0,
                      source >= 0, source < wordCount, target >= 0, target < wordCount,
                      source > previousSource || (source == previousSource && target > previousTarget),
                      loaded.count < 32_768 else { return nil }
                starts[source + 1] += 1
                guard starts[source + 1] <= 24 else { return nil }
                totals[source] += count
                loaded.append(Edge(target: Int32(target), score: count))
                previousSource = source
                previousTarget = target
            }
        }
        guard hasLexiconCount, priors.allSatisfy(\.isFinite), !loaded.isEmpty else { return nil }
        for source in 0..<wordCount {
            starts[source + 1] += starts[source]
            for index in Int(starts[source])..<Int(starts[source + 1]) {
                let target = Int(loaded[index].target)
                let prior = target < lexicon.count ? lexicon.logPrior[target] : priors[target - lexicon.count]
                let conditional = loaded[index].score / totals[source]
                loaded[index].score = log(0.8 * conditional + 0.2 * exp(prior))
            }
        }
        self.lexicon = lexicon
        self.edges = loaded
        self.edgeStart = starts
        self.extraPriors = priors
        self.alphabetical = (0..<wordCount).map(Int32.init).sorted { left, right in
            let lhs = Int(left), rhs = Int(right)
            let leftLength = Self.length(lhs, lexicon: lexicon)
            let rightLength = Self.length(rhs, lexicon: lexicon)
            for offset in 0..<min(leftLength, rightLength) {
                let l = Self.letter(lhs, offset: offset, lexicon: lexicon)
                let r = Self.letter(rhs, offset: offset, lexicon: lexicon)
                if l != r { return l < r }
            }
            return leftLength < rightLength
        }
    }

    func contains(_ word: String) -> Bool {
        guard let letters = Self.letters(word) else { return false }
        return lookup(letters) != nil
    }

    /// System checker / supplementary-lexicon candidates use the same frequency scale.
    /// Unknown names remain eligible but never pretend to have a corpus observation.
    func languageScore(_ word: String, previousWord: String?) -> Float {
        guard let letters = Self.letters(word), let id = lookup(letters) else { return -15 }
        return score(id, previous: previousID(previousWord))
    }

    func suggestions(for context: EnglishSuggestionContext, limit: Int = 8) -> [Suggestion] {
        guard limit > 0 else { return [] }
        let previous = previousID(context.previousWord)
        var best: [RankedWord] = []
        best.reserveCapacity(limit)

        func offer(_ id: Int, bonus: Float, correction: Bool) {
            let value = score(id, previous: previous) + bonus
            if let existing = best.firstIndex(where: { $0.id == id }) {
                if best[existing].score >= value { return }
                best.remove(at: existing)
            }
            let insertion = best.firstIndex { value > $0.score || (value == $0.score && id < $0.id) } ?? best.count
            guard insertion < limit else { return }
            best.insert(RankedWord(id: id, score: value, correction: correction), at: insertion)
            if best.count > limit { best.removeLast() }
        }

        if context.partialWord.isEmpty {
            guard context.allowsNextWord else { return [] }
            if let previous {
                for index in Int(edgeStart[previous])..<Int(edgeStart[previous + 1]) {
                    offer(Int(edges[index].target), bonus: 0, correction: false)
                }
            }
            // Highest-frequency general words are sufficient for unigram backoff.
            for id in 0..<min(32, lexicon.count) { offer(id, bonus: 0, correction: false) }
            offer(lexicon.count, bonus: 0, correction: false)
            offer(lexicon.count + 1, bonus: 0, correction: false)
        } else {
            guard let partial = Self.letters(context.partialWord), !partial.isEmpty,
                  partial.count <= SwipeLexicon.maxWordLength else { return [] }
            let normalizedTyped = EnglishSuggestionContext.normalized(context.partialWord)
            let exact = lookup(partial)
            let hasApostrophe = context.partialWord.contains(where: EnglishSuggestionContext.isApostrophe)
            var position = lowerBound(partial)
            while position < alphabetical.count {
                let id = Int(alphabetical[position])
                guard hasPrefix(id, letters: partial) else { break }
                // An explicitly typed apostrophe must not disappear in a completion.
                // Unrepresented contraction variants fall back to UITextChecker.
                let spelling = (id == exact || hasApostrophe) ? EnglishSuggestionContext.normalized(output(id)) : nil
                if spelling != normalizedTyped && (!hasApostrophe || spelling?.hasPrefix(normalizedTyped) == true) {
                    let extraLength = Self.length(id, lexicon: lexicon) - partial.count
                    offer(id, bonus: 1.5 - 0.35 * Float(min(extraLength, 6)), correction: id == exact)
                }
                position += 1
            }
            // Do not turn already-valid words into other words. Adjacent swaps are one
            // edit, alongside insertion/deletion/substitution. All are manual choices.
            if exact == nil && partial.count >= 3 {
                var edited = partial
                edited.reserveCapacity(partial.count + 1)
                for index in edited.indices {
                    let original = edited[index]
                    for letter in UInt8(0)..<26 where letter != original {
                        edited[index] = letter
                        if let id = lookup(edited) { offer(id, bonus: -2.3, correction: true) }
                    }
                    edited[index] = original
                }
                for index in 0..<(edited.count - 1) where edited[index] != edited[index + 1] {
                    edited.swapAt(index, index + 1)
                    if let id = lookup(edited) { offer(id, bonus: -1.3, correction: true) }
                    edited.swapAt(index, index + 1)
                }
                for index in partial.indices {
                    let removed = edited.remove(at: index)
                    if let id = lookup(edited) { offer(id, bonus: -2.3, correction: true) }
                    edited.insert(removed, at: index)
                }
                if partial.count < SwipeLexicon.maxWordLength {
                    for index in 0...partial.count {
                        edited.insert(0, at: index)
                        for letter in UInt8(0)..<26 {
                            edited[index] = letter
                            if let id = lookup(edited) { offer(id, bonus: -2.3, correction: true) }
                        }
                        edited.remove(at: index)
                    }
                }
            }
        }
        let normalizedPartial = EnglishSuggestionContext.normalized(context.partialWord)
        return best.compactMap { ranked in
            let word = context.matchCasing(output(ranked.id))
            guard EnglishSuggestionContext.normalized(word) != normalizedPartial
            else { return nil }
            return Suggestion(text: word, score: ranked.score, isCorrection: ranked.correction,
                              usesContext: previous.map { edgeStart[$0] != edgeStart[$0 + 1] } ?? false)
        }
    }

    private func previousID(_ word: String?) -> Int? {
        guard let word, let letters = Self.letters(word) else { return nil }
        return lookup(letters)
    }

    private func score(_ id: Int, previous: Int?) -> Float {
        let prior = id < lexicon.count ? lexicon.logPrior[id] : extraPriors[id - lexicon.count]
        guard let previous, edgeStart[previous] != edgeStart[previous + 1] else { return prior }
        var low = Int(edgeStart[previous])
        var high = Int(edgeStart[previous + 1])
        while low < high {
            let middle = (low + high) / 2
            if Int(edges[middle].target) < id { low = middle + 1 } else { high = middle }
        }
        if low < Int(edgeStart[previous + 1]), Int(edges[low].target) == id { return edges[low].score }
        return prior + Self.backoff
    }

    private func output(_ id: Int) -> String {
        if id == lexicon.count { return "a" }
        if id == lexicon.count + 1 { return "I" }
        return lexicon.outputWord(at: id)
    }

    private static func letters(_ word: String) -> [UInt8]? {
        var result: [UInt8] = []
        result.reserveCapacity(word.utf8.count)
        for scalar in word.lowercased().unicodeScalars {
            if scalar == "'" || scalar == "’" { continue }
            guard scalar.value >= 97, scalar.value <= 122 else { return nil }
            result.append(UInt8(scalar.value - 97))
        }
        return result.isEmpty ? nil : result
    }

    private static func length(_ id: Int, lexicon: SwipeLexicon) -> Int {
        id < lexicon.count ? Int(lexicon.wordStart[id + 1] - lexicon.wordStart[id]) : 1
    }

    private static func letter(_ id: Int, offset: Int, lexicon: SwipeLexicon) -> UInt8 {
        if id >= lexicon.count { return id == lexicon.count ? 0 : 8 }
        return lexicon.letters[Int(lexicon.wordStart[id]) + offset]
    }

    private func lowerBound(_ letters: [UInt8]) -> Int {
        var low = 0, high = alphabetical.count
        while low < high {
            let middle = (low + high) / 2
            if compare(Int(alphabetical[middle]), to: letters) < 0 { low = middle + 1 } else { high = middle }
        }
        return low
    }

    private func lookup(_ letters: [UInt8]) -> Int? {
        let position = lowerBound(letters)
        guard position < alphabetical.count else { return nil }
        let id = Int(alphabetical[position])
        return compare(id, to: letters) == 0 ? id : nil
    }

    private func compare(_ id: Int, to letters: [UInt8]) -> Int {
        let length = Self.length(id, lexicon: lexicon)
        for index in 0..<min(length, letters.count) {
            let letter = Self.letter(id, offset: index, lexicon: lexicon)
            if letter != letters[index] { return letter < letters[index] ? -1 : 1 }
        }
        return length == letters.count ? 0 : (length < letters.count ? -1 : 1)
    }

    private func hasPrefix(_ id: Int, letters: [UInt8]) -> Bool {
        guard Self.length(id, lexicon: lexicon) >= letters.count else { return false }
        for index in letters.indices where Self.letter(id, offset: index, lexicon: lexicon) != letters[index] {
            return false
        }
        return true
    }
}
