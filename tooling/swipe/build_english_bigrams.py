#!/usr/bin/env python3
"""Build the bounded, offline English suggestion bigrams (no duplicate word list).

Sources: https://norvig.com/ngrams/count_2w.txt and count_1w.txt, derived from
Google's Web Trillion Word Corpus: https://norvig.com/ngrams/ (2008/2009).
Norvig's page licenses its CODE under MIT; this attribution does not establish a
separate redistribution license for the corpus. These are web frequencies, not a
conversational language model, personalized data, or SwiftKey model data.

Vocabulary: IDs 0..N-1 refer to the EXISTING swipe-lexicon-en.txt in exact row
order. Only the two English one-letter words excluded by swipe ('a', 'i') are
added at IDs N and N+1, with count_1w priors. No hand-authored phrase counts.
Keep lowercase ASCII words present in that vocabulary, at most 24 successors per
predecessor, then the 32,768 highest-count pairs globally. Ties are lexical.
Counts are unmodified corpus counts; runtime normalizes over retained successors
and backs off to unigram frequency. Missing/rare contexts have unigram fallback.
Output contains integer IDs/counts, two one-letter log priors and input hashes.

Usage:
  python3 tooling/swipe/build_english_bigrams.py /tmp/count_2w.txt \
    /tmp/count_1w.txt SnipKeyboard/Resources/swipe-lexicon-en.txt \
    SnipKeyboard/Resources/english-bigrams-en.tsv
"""

import argparse
from collections import defaultdict
import hashlib
import math
from pathlib import Path

MAX_SUCCESSORS = 24
MAX_PAIRS = 32_768


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('bigrams', type=Path)
    parser.add_argument('unigrams', type=Path)
    parser.add_argument('lexicon', type=Path)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    lexicon = [line.split('\t') for line in args.lexicon.read_text().splitlines()]
    vocabulary = {word: index for index, (word, _) in enumerate(lexicon)}
    if len(vocabulary) != len(lexicon) or len(vocabulary) < 1_000:
        raise ValueError('Invalid swipe lexicon')
    extra_counts = {}
    for line in args.unigrams.read_text().splitlines():
        word, count = line.split('\t')
        if word in ('a', 'i'):
            extra_counts[word] = int(count)
    if set(extra_counts) != {'a', 'i'}:
        raise ValueError('Missing one-letter word counts')
    total = sum(int(count) for _, count in lexicon) + sum(extra_counts.values())
    for word in ('a', 'i'):
        vocabulary[word] = len(vocabulary)
    successors = defaultdict(list)
    seen = set()
    for line_number, line in enumerate(args.bigrams.read_text().splitlines(), 1):
        pair, raw_count = line.split('\t')
        words = pair.split(' ')
        if len(words) != 2:
            raise ValueError(f'Malformed pair on line {line_number}')
        left, right = words
        count = int(raw_count)
        if count <= 0:
            raise ValueError(f'Nonpositive count on line {line_number}')
        if left not in vocabulary or right not in vocabulary:
            continue
        if (left, right) in seen:
            raise ValueError(f'Duplicate pair on line {line_number}')
        seen.add((left, right))
        successors[left].append((right, count))
    kept = []
    for left, rows in successors.items():
        rows.sort(key=lambda row: (-row[1], row[0]))
        kept.extend((left, right, count) for right, count in rows[:MAX_SUCCESSORS])
    kept.sort(key=lambda row: (-row[2], row[0], row[1]))
    kept = kept[:MAX_PAIRS]
    kept.sort(key=lambda row: (vocabulary[row[0]], vocabulary[row[1]]))
    header = [
        '# snipkey-english-bigrams-v1',
        '# source https://norvig.com/ngrams/count_2w.txt',
        f'# bigrams_sha256 {digest(args.bigrams)}',
        f'# unigrams_sha256 {digest(args.unigrams)}',
        f'# lexicon_sha256 {digest(args.lexicon)}',
        f'# limits successors={MAX_SUCCESSORS} pairs={MAX_PAIRS}',
        f'@lexicon\t{len(lexicon)}',
        *(f'@{word}\t{math.log(extra_counts[word] / total):.9f}' for word in ('a', 'i')),
    ]
    rows = [f'{vocabulary[left]}\t{vocabulary[right]}\t{count}' for left, right, count in kept]
    args.output.write_text('\n'.join(header + rows) + '\n', encoding='ascii')
    print(f'{len(kept)} pairs, {len({left for left, _, _ in kept})} predecessor words')
    print(f'{args.output.stat().st_size} bytes; resource sha256 {digest(args.output)}')
    for label in ('bigrams', 'unigrams', 'lexicon'):
        print(f'{label} sha256 {digest(getattr(args, label))}')


if __name__ == '__main__':
    main()
