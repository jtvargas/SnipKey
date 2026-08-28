#!/usr/bin/env python3
"""
Build trigram-en.bin — the bundled character-trigram language model for the V2 keyboard
(V2_KEYBOARD_NEXTGEN_PLAN §7 Stage 2).

Input:  Peter Norvig's count_1w.txt (333k English words + Google Trillion Word Corpus
        frequencies): https://norvig.com/ngrams/count_1w.txt
        (Download it yourself; the corpus is NOT committed to the repo.)

Model:  Within-word character trigrams over a 27-symbol alphabet (a–z + '^' word
        boundary), frequency-weighted by word count, pre-smoothed OFFLINE by linear
        interpolation so the keyboard runtime does zero backoff math:

            P(next | p2, p1) = 0.70·P_tri + 0.25·P_bi(next | p1) + 0.05·P_uni(next)

        Contexts with no trigram mass renormalize onto the bigram+unigram terms.
        Every row sums to 1 (±1e-6). Note the table subsumes the runtime's other
        tables: row (^, c) is the letter bigram and row (^, ^) is the word-initial
        distribution, both derived from the same corpus.

Output: 16-byte header {magic 'SKT1', version u32, count u32, crc32 u32 of payload}
        + 27×27×26 float32 little-endian payload (75,816 bytes ≈ 74 KB).

Usage:  python3 tooling/trigram/build_trigram_table.py <count_1w.txt> <output.bin>
"""

import struct
import sys
import zlib

BOUNDARY = 26  # index of '^'
W_TRI, W_BI, W_UNI = 0.70, 0.25, 0.05


def letter_index(ch: str) -> int:
    return ord(ch) - 97


def main() -> int:
    if len(sys.argv) != 3:
        print(__doc__)
        return 1
    corpus_path, out_path = sys.argv[1], sys.argv[2]

    tri = [[0.0] * 26 for _ in range(27 * 27)]   # (p2*27+p1) -> next counts
    bi = [[0.0] * 26 for _ in range(27)]         # p1 -> next counts
    uni = [0.0] * 26

    words = 0
    with open(corpus_path) as f:
        for line in f:
            parts = line.split()
            if len(parts) != 2:
                continue
            word, count_s = parts
            if not word.isascii() or not word.isalpha():
                continue
            count = float(count_s)
            word = word.lower()
            words += 1
            p2, p1 = BOUNDARY, BOUNDARY
            for ch in word:
                nxt = letter_index(ch)
                tri[p2 * 27 + p1][nxt] += count
                bi[p1][nxt] += count
                uni[nxt] += count
                p2, p1 = p1, nxt

    if words < 1000:
        print(f"ERROR: only {words} usable words — wrong corpus file?")
        return 1

    def normalized(row):
        total = sum(row)
        return [v / total for v in row] if total > 0 else None

    uni_p = normalized(uni)
    bi_p = [normalized(bi[i]) for i in range(27)]

    payload = bytearray()
    for p2 in range(27):
        for p1 in range(27):
            tri_p = normalized(tri[p2 * 27 + p1])
            bi_row = bi_p[p1] or uni_p
            out = []
            for nxt in range(26):
                if tri_p is not None:
                    p = W_TRI * tri_p[nxt] + W_BI * bi_row[nxt] + W_UNI * uni_p[nxt]
                else:
                    # No trigram mass for this context — renormalize onto bi+uni.
                    p = (W_BI * bi_row[nxt] + W_UNI * uni_p[nxt]) / (W_BI + W_UNI)
                out.append(p)
            total = sum(out)
            payload.extend(struct.pack("<26f", *(v / total for v in out)))

    count = 27 * 27 * 26
    header = struct.pack("<4sII", b"SKT1", 1, count) + struct.pack("<I", zlib.crc32(payload) & 0xFFFFFFFF)
    with open(out_path, "wb") as f:
        f.write(header)
        f.write(payload)

    print(f"Wrote {out_path}: {len(header) + len(payload)} bytes from {words} words")
    # Sanity: report the classic contexts.
    def row(p2, p1):
        base = (p2 * 27 + p1) * 26 * 4
        return struct.unpack_from("<26f", payload, base)
    th = row(letter_index("t"), letter_index("h"))
    qu = row(BOUNDARY, letter_index("q"))
    print(f"P(e | t,h) = {th[letter_index('e')]:.3f}   P(u | ^,q) = {qu[letter_index('u')]:.3f}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
