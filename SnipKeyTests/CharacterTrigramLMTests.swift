//
//  CharacterTrigramLMTests.swift
//  SnipKeyTests
//
//  Sanity for the bundled corpus trigram: the resource loads (magic/CRC pass), rows are
//  proper distributions, and the classic English contexts behave — plus the deliberate
//  rare-char case that the resolver's β clamp depends on.
//

import XCTest
@testable import SnipKey

final class CharacterTrigramLMTests: XCTestCase {

    private func row(prev2: Character?, prev1: Character?) -> ContiguousArray<Float> {
        var buf = ContiguousArray<Float>(repeating: 0, count: 26)
        XCTAssertTrue(CharacterTrigramLM.shared.fill(into: &buf, prev2: prev2, prev1: prev1),
                      "trigram-en.bin failed to load — resource missing or corrupt")
        return buf
    }

    private func idx(_ c: Character) -> Int { Int(c.asciiValue! - 97) }

    func testResourceLoads() {
        XCTAssertTrue(CharacterTrigramLM.shared.isLoaded)
        XCTAssertEqual(CharacterTrigramLM.shared.table.count, 27 * 27 * 26)
    }

    func testRowsAreDistributions() {
        // Spot-check a spread of contexts, including boundary rows.
        let contexts: [(Character?, Character?)] = [
            (nil, nil), (nil, "t"), ("t", "h"), ("q", "u"), ("z", "z"), (nil, "q"),
        ]
        for (p2, p1) in contexts {
            let r = row(prev2: p2, prev1: p1)
            let sum = r.reduce(0, +)
            XCTAssertEqual(sum, 1.0, accuracy: 1e-3,
                           "row (\(String(describing: p2)), \(String(describing: p1))) sums to \(sum)")
            XCTAssertTrue(r.allSatisfy { $0 >= 0 })
        }
    }

    func testClassicEnglishContexts() {
        // "th" → e must dominate.
        let th = row(prev2: "t", prev1: "h")
        XCTAssertEqual(th.firstIndex(of: th.max()!), idx("e"))
        XCTAssertGreaterThan(th[idx("e")], 0.5)
        // "^q" → u nearly guaranteed.
        let q = row(prev2: nil, prev1: "q")
        XCTAssertGreaterThan(q[idx("u")], 0.8)
        // Word-initial: t is the most common English word-start.
        let initial = row(prev2: nil, prev1: nil)
        XCTAssertEqual(initial.firstIndex(of: initial.max()!), idx("t"))
    }

    func testContextIntegrationSwitchesSources() {
        // Corpus tuning ON: after "t","h" the context's weight(e) reflects the LM row.
        let corpusCtx = ProbabilisticTouchContext(tuning: ContextTuning(useCorpusTrigram: true))
        corpusCtx.recordCharacter("t")
        corpusCtx.recordCharacter("h")
        let expected = row(prev2: "t", prev1: "h")[idx("e")]
        XCTAssertEqual(corpusCtx.weight(for: "e"), expected, accuracy: 1e-5)

        // OFF: exact legacy behavior (bigram + curated boost).
        let legacyCtx = ProbabilisticTouchContext(tuning: ContextTuning(useCorpusTrigram: false))
        legacyCtx.recordCharacter("t")
        legacyCtx.recordCharacter("h")
        XCTAssertGreaterThanOrEqual(legacyCtx.weight(for: "e"), 0.5)
    }

    func testCRC32MatchesZlib() {
        // zlib.crc32(b"hello") == 0x3610A686 — pin the Swift implementation to it.
        XCTAssertEqual(CharacterTrigramLM.crc32(Data("hello".utf8)), 0x3610A686)
    }
}
