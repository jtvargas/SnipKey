//
//  SwipeLexicon.swift
//  SnipKeyboard
//
//  Bundled English word list + unigram log-prior that `SwipeDecoder` ranks swipe traces
//  against. Generated offline by tooling/swipe/build_swipe_lexicon.py from Norvig's
//  Google-corpus word frequencies. A shared corpus does not imply identical priors:
//  this lexicon filters and normalizes word counts independently of the trigram model.
//
//      python3 tooling/swipe/build_swipe_lexicon.py /tmp/count_1w.txt \
//          SnipKeyboard/Resources/swipe-lexicon-en.txt
//
//  File format: plain text, one `word<TAB>count` per line, descending count, no header.
//  Words are lowercase a–z, 2…20 letters, 50,000 entries (~790 KB on disk).
//
//  Resident layout: letters are stored as one flat index array (0 = a … 25 = z)
//  with per-word offsets rather than 50k Strings. Strings are materialized only for
//  returned candidates. A (first letter, last letter) bucket index narrows enumeration.
//
//  Loaded once, off the main thread; a failed load leaves swipe typing unavailable.
//

import Foundation

final class SwipeLexicon: Sendable {

    static let letterCount = 26
    static let minWordLength = 2
    static let maxWordLength = 20
    /// A healthy file has 50k lines; anything far below means the resource is damaged.
    private static let minimumUsableWords = 1_000

    /// Number of words in the lexicon.
    let count: Int
    /// Letter indices (0 = a … 25 = z) of every word, concatenated in lexicon order.
    /// Word `i` occupies `letters[wordStart[i] ..< wordStart[i + 1]]`.
    let letters: [UInt8]
    /// `count + 1` offsets into `letters`.
    let wordStart: [Int32]
    /// `ln(count_i / Σ count)` per word — the decoder's frequency prior.
    let logPrior: [Float]
    /// CSR bucket index: words whose first letter is `f` and last letter is `l` are
    /// `bucketWords[bucketStart[f * 26 + l] ..< bucketStart[f * 26 + l + 1]]`, in lexicon
    /// (descending-frequency) order.
    private let bucketStart: [Int32]
    private let bucketWords: [Int32]

    /// Apostrophe-free spellings → the contraction the keyboard should actually insert.
    /// Output-only: the trace is matched against the bare spelling (there is no apostrophe
    /// key on the swipe path), then rewritten here. Rule: a stem is mapped when its bare
    /// spelling is not ordinarily used as a standalone word. `were`, `well`, `ill`,
    /// `id`, `its` remain literal; `cant`/`wont`/`lets` prefer contractions. This is a
    /// product spelling policy, not context-aware disambiguation or platform parity.
    /// `im`/`ive` also capitalize the I.
    /// tooling/swipe/build_swipe_lexicon.py keeps these stems through its dictionary gate
    /// (CONTRACTION_STEMS) — keep the two lists in sync.
    static let contractions: [String: String] = [
        "dont": "don't", "cant": "can't", "wont": "won't",
        "im": "I'm", "ive": "I've",
        "youre": "you're", "youve": "you've", "youll": "you'll",
        "theyre": "they're", "theyve": "they've",
        "thats": "that's", "whats": "what's", "lets": "let's",
        "hes": "he's", "shes": "she's",
        "didnt": "didn't", "doesnt": "doesn't", "isnt": "isn't", "wasnt": "wasn't",
        "arent": "aren't", "werent": "weren't", "havent": "haven't", "hasnt": "hasn't",
        "couldnt": "couldn't", "wouldnt": "wouldn't", "shouldnt": "shouldn't",
        "theres": "there's", "heres": "here's", "whos": "who's", "wheres": "where's",
        "hows": "how's",
    ]

    // MARK: - Loading

    /// Reads `swipe-lexicon-en.txt` from the main bundle and parses it on the calling
    /// thread. Call off-main.
    static func loadBundled() -> SwipeLexicon? {
        guard let url = Bundle.main.url(forResource: "swipe-lexicon-en", withExtension: "txt"),
              let data = try? Data(contentsOf: url)
        else { return nil }
        return SwipeLexicon(data: data)
    }

    /// Parses the `word<TAB>count` text format. Returns nil on any malformed line — the
    /// file is generated, so damage means a bad build, not user input.
    init?(data: Data) {
        var letters: [UInt8] = []
        var wordStart: [Int32] = [0]
        var counts: [Double] = []
        var firstLast: [(UInt8, UInt8)] = []
        letters.reserveCapacity(data.count / 2)
        wordStart.reserveCapacity(50_001)
        counts.reserveCapacity(50_000)
        firstLast.reserveCapacity(50_000)

        let ok: Bool = data.withUnsafeBytes { raw -> Bool in
            let bytes = raw.bindMemory(to: UInt8.self)
            var i = 0
            let n = bytes.count
            while i < n {
                // Word: lowercase a–z up to the tab.
                let wordBegin = letters.count
                while i < n, bytes[i] >= UInt8(ascii: "a"), bytes[i] <= UInt8(ascii: "z") {
                    letters.append(bytes[i] - UInt8(ascii: "a"))
                    i += 1
                }
                let length = letters.count - wordBegin
                guard length >= Self.minWordLength, length <= Self.maxWordLength,
                      i < n, bytes[i] == UInt8(ascii: "\t")
                else { return false }
                i += 1
                // Count: decimal digits up to the newline (or EOF).
                var value = 0.0
                var digits = 0
                while i < n, bytes[i] >= UInt8(ascii: "0"), bytes[i] <= UInt8(ascii: "9") {
                    value = value * 10 + Double(bytes[i] - UInt8(ascii: "0"))
                    digits += 1
                    i += 1
                }
                guard digits > 0, value > 0, value.isFinite else { return false }
                if i < n, bytes[i] == UInt8(ascii: "\r") { i += 1 }
                if i < n {
                    guard bytes[i] == UInt8(ascii: "\n") else { return false }
                    i += 1
                }
                counts.append(value)
                firstLast.append((letters[wordBegin], letters[letters.count - 1]))
                wordStart.append(Int32(letters.count))
            }
            return true
        }
        guard ok, counts.count >= Self.minimumUsableWords else { return nil }

        let total = counts.reduce(0, +)
        guard total.isFinite, total > 0 else { return nil }
        self.count = counts.count
        self.letters = letters
        self.wordStart = wordStart
        let logTotal = log(total)
        self.logPrior = counts.map { Float(log($0) - logTotal) }

        // Counting sort into (first, last) buckets; stable, so each bucket stays in
        // descending-frequency order.
        let bucketCount = Self.letterCount * Self.letterCount
        var sizes = [Int32](repeating: 0, count: bucketCount + 1)
        for (f, l) in firstLast { sizes[Int(f) * Self.letterCount + Int(l) + 1] += 1 }
        for b in 0..<bucketCount { sizes[b + 1] += sizes[b] }
        var fill = sizes
        var bucketWords = [Int32](repeating: 0, count: counts.count)
        for (index, (f, l)) in firstLast.enumerated() {
            let b = Int(f) * Self.letterCount + Int(l)
            bucketWords[Int(fill[b])] = Int32(index)
            fill[b] += 1
        }
        self.bucketStart = sizes
        self.bucketWords = bucketWords
    }

    // MARK: - Queries

    /// Lexicon indices of words starting with letter `first` and ending with `last`
    /// (0 = a … 25 = z), most frequent first.
    func bucket(first: Int, last: Int) -> ArraySlice<Int32> {
        let b = first * Self.letterCount + last
        return bucketWords[Int(bucketStart[b]) ..< Int(bucketStart[b + 1])]
    }

    /// Range of `letters` holding word `index`.
    func letterRange(of index: Int) -> Range<Int> {
        Int(wordStart[index]) ..< Int(wordStart[index + 1])
    }

    /// The bare lowercase spelling of word `index`.
    func word(at index: Int) -> String {
        let range = letterRange(of: index)
        return String(unsafeUninitializedCapacity: range.count) { buffer in
            for (k, j) in range.enumerated() { buffer[k] = letters[j] + UInt8(ascii: "a") }
            return range.count
        }
    }

    /// The spelling the keyboard should insert for word `index`: the contraction when
    /// `contractions` has one, otherwise the bare word.
    func outputWord(at index: Int) -> String {
        let bare = word(at: index)
        return Self.contractions[bare] ?? bare
    }
}
