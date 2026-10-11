#!/usr/bin/env python3
"""
Build swipe-lexicon-en.txt — the bundled English word list + frequency prior that the V2
keyboard's swipe decoder (SwipeDecoder.swift, SHARK2-style shape/location matching) ranks
candidates against.

Input:  Peter Norvig's count_1w.txt (333k English words + Google Trillion Word Corpus
        frequencies): https://norvig.com/ngrams/count_1w.txt
        (Download it yourself; the corpus is NOT committed to the repo.)
        Corpus description: https://norvig.com/ngrams/
        This source attribution is not a redistribution-license determination.

        /usr/share/dict/words (macOS Web2 dictionary) is used as a dictionary gate;
        --dictionary accepts a pinned copy on other machines. Its local README says
        the 1934 copyright has lapsed according to its supplier; dictionary versions vary.

Filter: keep a word when ALL of
          - lowercase ASCII a–z only (the corpus is already lowercased; this drops
            digits/punctuation),
          - length 2…20 (1-letter words can't be swiped — a swipe commits ≥2 letters;
            >20 is noise),
          - it is in /usr/share/dict/words (case-insensitive) OR within the top 5,000
            corpus entries by count (keeps common forms the dictionary lacks — plurals,
            "ok", "http" — while dropping URL fragments / junk like "fws" that only
            appear deep in the tail) OR it is a CONTRACTION_STEM (apostrophe-free
            spelling such as "didnt" that SwipeLexicon.contractions rewrites to
            "didn't" on output; the dictionary has none of them).
        Then keep the top 50,000 by count.

Output: plain text, one `word<TAB>count` per line, descending count, no header.
        SwipeLexicon.swift parses it at load. Input/output SHA-256 hashes are printed
        so a generated resource can be traced to exact inputs.

Usage:  python3 tooling/swipe/build_swipe_lexicon.py <count_1w.txt> <output.txt>
        Add --dictionary <path> to reproduce with a specific dictionary snapshot.

Observed available input snapshots and resource (verify regeneration before replacing):
  corpus:     51df159fd3de12b20e403c108f526e96dbd723d9cabdd5f17955cdc16059e690
  dictionary: be41ad97963bf8dabedd5871d5d691596175269d540956b0f9965a885c2bbab9
  resource:   01ff563cdecb425b572ae3aa20cb7ea6c9400ef8f2599143ae3917ce7bb92dd8
"""

import argparse
import hashlib
from pathlib import Path
import sys

DICT_PATH = "/usr/share/dict/words"
MIN_LEN, MAX_LEN = 2, 20
TOP_BY_COUNT_BYPASS = 5_000   # corpus rank below which the dictionary gate is skipped
KEEP = 50_000
# Keys of SwipeLexicon.contractions (keep in sync). Stems that are also common words in
# their own right (were/well/ill/id/its) are not mapped and need no bypass.
CONTRACTION_STEMS = {
    "dont", "cant", "wont", "im", "ive", "youre", "youve", "youll", "theyre", "theyve",
    "thats", "whats", "lets", "hes", "shes", "didnt", "doesnt", "isnt", "wasnt", "arent",
    "werent", "havent", "hasnt", "couldnt", "wouldnt", "shouldnt", "theres", "heres",
    "whos", "wheres", "hows",
}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("corpus", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--dictionary", type=Path, default=Path(DICT_PATH))
    args = parser.parse_args()
    corpus_path, out_path = args.corpus, args.output

    with args.dictionary.open(encoding="utf-8") as f:
        dictionary = {line.strip().lower() for line in f}
    if len(dictionary) < 10_000:
        print(f"ERROR: only {len(dictionary)} dictionary words at {args.dictionary}")
        return 1

    counts: dict[str, int] = {}
    with corpus_path.open(encoding="utf-8") as f:
        for line_number, line in enumerate(f, 1):
            parts = line.split()
            if len(parts) != 2:
                raise ValueError(f"Malformed corpus line {line_number}")
            word, count_s = parts
            count = int(count_s)
            if count <= 0 or word in counts:
                raise ValueError(f"Nonpositive count or duplicate word on line {line_number}")
            counts[word] = count

    # Rank BEFORE the dictionary bypass, so input order cannot change which words pass.
    ranked = sorted(counts.items(), key=lambda wc: (-wc[1], wc[0]))
    kept: list[tuple[str, int]] = []
    for rank, (word, count) in enumerate(ranked, 1):
        if not (MIN_LEN <= len(word) <= MAX_LEN):
            continue
        if not word.isascii() or not word.isalpha() or not word.islower():
            continue
        if rank > TOP_BY_COUNT_BYPASS and word not in dictionary and word not in CONTRACTION_STEMS:
            continue
        kept.append((word, count))

    if len(kept) < 1000:
        print(f"ERROR: only {len(kept)} usable words — wrong corpus file?")
        return 1

    # Filtering preserves the deterministic count/word order.
    kept = kept[:KEEP]

    with open(out_path, "w", encoding="ascii", newline="\n") as f:
        for word, count in kept:
            f.write(f"{word}\t{count}\n")

    total = sum(c for _, c in kept)
    print(f"Wrote {out_path}: {len(kept)} words, total count {total}")
    print(f"first: {kept[0][0]}  last: {kept[-1][0]} ({kept[-1][1]})")
    for label, path in (("corpus", corpus_path), ("dictionary", args.dictionary), ("resource", out_path)):
        print(f"{label} sha256: {hashlib.sha256(path.read_bytes()).hexdigest()}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
