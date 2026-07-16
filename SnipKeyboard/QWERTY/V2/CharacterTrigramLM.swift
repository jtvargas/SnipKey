//
//  CharacterTrigramLM.swift
//  SnipKeyboard
//
//  Bundled corpus-trained character trigram (plan §7 Stage 2): P(next | prev2, prev1)
//  over a 27-symbol alphabet (a–z + '^' word boundary), generated offline by
//  tooling/trigram/build_trigram_table.py from Norvig's Google-corpus word frequencies,
//  pre-smoothed (0.70 tri / 0.25 bi / 0.05 uni interpolation) so the runtime does ZERO
//  backoff math. Row (^,c) is the corpus bigram; row (^,^) the word-initial distribution.
//
//  ~74 KB resident (0.25% of the extension's ~30 MB jetsam budget), loaded once at first
//  context init (off the touch path) and validated (magic/version/count/CRC32). A failed
//  load degrades silently to the legacy BigramEngine + curated TrigramEngine path.
//

import Foundation

final class CharacterTrigramLM {

    static let shared = CharacterTrigramLM()

    private static let symbols = 27      // a–z + '^'
    private static let letters = 26
    private static let expectedCount = symbols * symbols * letters

    private(set) var table: ContiguousArray<Float> = []
    var isLoaded: Bool { !table.isEmpty }

    private init() {
        load()
    }

    /// Copy P(next | prev2, prev1) into a caller-owned 26-slot buffer (nil = word
    /// boundary '^'). One memcpy-sized loop, zero allocations. Returns false when the
    /// table isn't loaded — the caller falls back to the legacy tables.
    @discardableResult
    func fill(into buffer: inout ContiguousArray<Float>, prev2: Character?, prev1: Character?) -> Bool {
        guard !table.isEmpty else { return false }
        let p2 = prev2.flatMap { BigramEngine.letterIndex($0) } ?? 26
        let p1 = prev1.flatMap { BigramEngine.letterIndex($0) } ?? 26
        let base = (p2 * Self.symbols + p1) * Self.letters
        for i in 0..<Self.letters { buffer[i] = table[base + i] }
        return true
    }

    private func load() {
        guard let url = Bundle.main.url(forResource: "trigram-en", withExtension: "bin"),
              let data = try? Data(contentsOf: url),
              data.count == 16 + Self.expectedCount * MemoryLayout<Float>.size
        else { return }

        let magicOK = data.prefix(4).elementsEqual("SKT1".utf8)
        let version = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 4, as: UInt32.self) }
        let count = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 8, as: UInt32.self) }
        let storedCRC = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 12, as: UInt32.self) }
        guard magicOK, version == 1, count == UInt32(Self.expectedCount) else { return }

        let payload = data.subdata(in: 16..<data.count)
        guard Self.crc32(payload) == storedCRC else { return }

        table = payload.withUnsafeBytes { raw in
            ContiguousArray(raw.bindMemory(to: Float.self))
        }
    }

    // MARK: - CRC32 (IEEE, matches Python zlib.crc32)

    private static let crcTable: [UInt32] = (0..<256).map { i -> UInt32 in
        var c = UInt32(i)
        for _ in 0..<8 {
            c = (c & 1) == 1 ? (0xEDB88320 ^ (c >> 1)) : (c >> 1)
        }
        return c
    }

    static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        for byte in data {
            crc = crcTable[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
        }
        return crc ^ 0xFFFFFFFF
    }
}
