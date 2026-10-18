//
//  TypingContextMirror.swift
//  SnipKeyboard
//
//  Keyboard-side mirror of the text immediately before the caret.
//
//  Every proxy mutation we make (insert, delete, paste, snippet) is replayed here in
//  lockstep, so auto-capitalization, smart punctuation and word-tier backspace answer
//  from local memory instead of a synchronous cross-process `documentContextBeforeInput`
//  read on the keystroke path. The mirror is re-synced from ONE real read only off that
//  path: the coalesced side-effect flush, `viewWillAppear`, and external document /
//  selection changes reported by the host.
//
//  SwiftKey's `SKShiftStateManager` follows the same model — shift state is derived by a
//  local tokenizer over its own context mirror; the host is never read per keystroke.
//

import UIKit

@MainActor
final class TypingContextMirror {

    /// Trailing characters retained after a trim. Covers every consumer with margin:
    /// auto-cap inspects ≤ 2 trailing characters, smart punctuation ≤ 4, auto-cap-"I" ≤ 3,
    /// and a word-tier backspace tick removes at most 30 (`wordDeletionChunk`).
    nonisolated static let capacity = 64

    /// Grapheme clusters before the caret, oldest first. `[Character]` so append / pop are
    /// O(1) and suffix inspection never re-walks a String's grapheme breaks. The buffer is
    /// reserved at twice `capacity` and only compacted when full, so a steady typing burst
    /// does one 64-element memmove per 64 keystrokes and never reallocates.
    private var tail: [Character]

    nonisolated init() {
        var buffer: [Character] = []
        buffer.reserveCapacity(2 * Self.capacity)
        tail = buffer
    }

    // MARK: - Reads

    var isEmpty: Bool { tail.isEmpty }

    var count: Int { tail.count }

    /// Character `offset` positions before the caret (0 = the one just before it).
    /// Nil past the start of the mirrored window.
    func character(fromEnd offset: Int) -> Character? {
        let index = tail.count - 1 - offset
        return index >= 0 ? tail[index] : nil
    }

    /// Up to `n` trailing characters, oldest first. A slice — no allocation.
    func lastCharacters(_ n: Int) -> ArraySlice<Character> {
        tail.suffix(n)
    }

    /// True when the mirrored text ends with `suffix`. Grapheme-wise comparison from the
    /// end; stops at the first mismatch, no allocation.
    func hasSuffix(_ suffix: String) -> Bool {
        var index = tail.count
        for ch in suffix.reversed() {
            index -= 1
            guard index >= 0, tail[index] == ch else { return false }
        }
        return true
    }

    /// The mirrored text as a String. Allocates — diagnostics / off-hot-path use only.
    var textBeforeCaret: String { String(tail) }

    // MARK: - Lockstep mutations

    /// Replay our own insert. Only the trailing `capacity` characters of a long insert
    /// (paste, snippet) are walked, so a multi-KB paste costs the same as a keystroke.
    func append(_ text: String) {
        for ch in text.suffix(Self.capacity) {
            tail.append(ch)
        }
        if tail.count >= 2 * Self.capacity {
            tail.removeFirst(tail.count - Self.capacity)
        }
    }

    /// Replay our own `deleteBackward()` calls. Pops one grapheme per deletion; the host's
    /// granularity for composed clusters (jamo, Indic sequences) can differ, which the
    /// next flush re-sync corrects. Deleting past the window is a no-op — the mirror does
    /// not know what text precedes it.
    func deleteBackward(count: Int = 1) {
        tail.removeLast(min(count, tail.count))
    }

    /// Re-sync from a real `documentContextBeforeInput` read. Keeps only the trailing
    /// `capacity` characters; nil (host exposes no context) clears the mirror.
    func reset(to context: String?) {
        tail.removeAll(keepingCapacity: true)
        guard let context else { return }
        for ch in context.suffix(Self.capacity) {
            tail.append(ch)
        }
    }

    // MARK: - Auto-capitalization

    /// Native auto-cap rule for the text before the caret. An empty mirror is treated as
    /// the start of the document (sentence start) — the same assumption the host-read
    /// implementation made when `documentContextBeforeInput` came back empty.
    ///
    /// `.sentences` capitalizes after `.` `!` `?` followed by one or more whitespace
    /// characters, after a newline, and when only whitespace precedes the caret.
    func needsCapitalization(for type: UITextAutocapitalizationType) -> Bool {
        switch type {
        case .none:
            return false
        case .allCharacters:
            return true
        case .words:
            guard let last = tail.last else { return true }
            return last.isWhitespace
        case .sentences:
            guard let last = tail.last else { return true }
            if last.isNewline { return true }
            guard last.isWhitespace else { return false }
            var index = tail.count - 1
            while index >= 0, tail[index].isWhitespace { index -= 1 }
            guard index >= 0 else { return true }
            return Self.isSentenceTerminator(tail[index])
        @unknown default:
            return false
        }
    }

    private static func isSentenceTerminator(_ ch: Character) -> Bool {
        ch == "." || ch == "!" || ch == "?"
    }
}
