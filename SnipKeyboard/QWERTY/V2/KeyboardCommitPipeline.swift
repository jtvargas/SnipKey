//
//  KeyboardCommitPipeline.swift
//  SnipKeyboard
//
//  Shared post-key-press side effects, used by the V2 gesture coordinator so that
//  auto-period and predictive triggers stay consistent across commit paths.
//
//  Smart-punctuation and auto-cap-"i" transforms (Phase E) run AFTER `insertText`
//  but BEFORE slash/predictive evaluation so the latter see the final text. Every
//  context decision here reads `QWERTYInputTracking.contextMirror` — the controller
//  advances it in lockstep with each proxy mutation — so no commit path performs a
//  synchronous `documentContextBeforeInput` read.
//

import UIKit

@MainActor
enum KeyboardCommitPipeline {

    /// Commit a single character with the current shift state. Handles casing,
    /// input tracking, shift state machine, slash/predictive evaluation.
    static func commitCharacter(
        _ char: String,
        state: QWERTYKeyboardState,
        actions: KeyboardActions
    ) {
      KeyboardSignposts.interval("commit") {
        let textToInsert: String
        switch state.shiftState {
        case .disabled: textToInsert = char.lowercased()
        case .enabled, .locked: textToInsert = char.uppercased()
        }

        // Smart space: if a predictive suggestion just inserted a trailing "smart space" and
        // the next character is punctuation, eat that space so the punctuation attaches to
        // the word ("word ." → "word."). Matches native iOS; only ever eats a space WE
        // inserted (flag-gated). Done before insert so smart-quotes see the right context.
        if state.inputTracking.pendingSmartSpace {
            state.inputTracking.pendingSmartSpace = false
            let eatSet: Set<String> = [".", ",", "!", "?", ";", ":", "'", ")", "]", "}", "\""]
            if eatSet.contains(textToInsert) { actions.deleteBackward() }
        }

        KeyboardSignposts.interval("insertXPC") {
            actions.insertText(textToInsert)
        }
        state.inputTracking.recordAction(.character)
        if let scalar = textToInsert.first {
            if scalar.isLetter {
                state.inputTracking.touchContext.recordCharacter(scalar)
            } else {
                state.inputTracking.touchContext.recordNonCharacter()
            }
        }
        state.handleShiftAfterCharacter()

        // Smart-punctuation transforms — only run if the host field allows them.
        let traits = actions.inputTraits()
        if traits.allowsSmartTransforms {
            applySmartPunctuation(justInserted: textToInsert, traits: traits,
                                  state: state, actions: actions)
        }

        // Defer slash + predictive evaluation off the synchronous touch path. The
        // coalesced flush reads context once (post-mutation, always fresh).
        actions.scheduleSideEffects()
      }
    }

    /// Commit a literal shortcut key such as `.com`, `@`, `#`, `.`, or `/`.
    /// These keys are layout affordances, not shift-cased character keys.
    static func commitText(
        _ text: String,
        state: QWERTYKeyboardState,
        actions: KeyboardActions
    ) {
        guard !text.isEmpty else { return }

        if state.inputTracking.pendingSmartSpace {
            state.inputTracking.pendingSmartSpace = false
            let eatSet: Set<Character> = [".", ",", "!", "?", ";", ":", "'", ")", "]", "}", "\""]
            if let first = text.first, eatSet.contains(first) {
                actions.deleteBackward()
            }
        }

        actions.insertText(text)
        if text.count == 1, let scalar = text.first, scalar.isLetter {
            state.inputTracking.recordAction(.character)
            state.inputTracking.touchContext.recordCharacter(scalar)
        } else {
            state.inputTracking.recordAction(.other)
            state.inputTracking.touchContext.recordNonCharacter()
        }

        actions.scheduleSideEffects()
    }

    /// Commit space. Inserts auto-period (". ") if the previous keystrokes were
    /// character + space + space. Otherwise inserts a normal space.
    static func commitSpace(
        state: QWERTYKeyboardState,
        actions: KeyboardActions
    ) {
        state.inputTracking.pendingSmartSpace = false
        if state.inputTracking.shouldInsertAutoPeriod() {
            // Replace the trailing space with ". " — the previous space already inserted,
            // so we delete it and insert ". ".
            actions.deleteBackward()
            actions.insertText(". ")
            state.inputTracking.resetAutoPeriodTracking()
        } else {
            actions.insertText(" ")
        }
        state.inputTracking.recordAction(.space)
        state.inputTracking.touchContext.recordNonCharacter()

        // After space, retroactively capitalize a lone "i" word ("i " → "I ").
        // Gated by the SnipKey-level Auto-Capitalization Setting and the host field's
        // keyboard type (URL/email skip smart transforms regardless).
        let traits = actions.inputTraits()
        if traits.autoCapitalizationEnabled && traits.allowsSmartTransforms {
            applyAutoCapitalizationOfI(state: state, actions: actions)
        }

        // Native iOS: typing space on the numbers or symbols page returns to the
        // letters page automatically (after the space is inserted). Covers the
        // common pattern of "jumped to 123 to type one symbol, now back to words."
        if state.currentPage != .letters {
            state.currentPage = .letters
        }

        // Deferred + coalesced; flush reads fresh post-mutation context once.
        actions.scheduleSideEffects()
    }

    /// Commit backspace.
    static func commitBackspace(
        state: QWERTYKeyboardState,
        actions: KeyboardActions
    ) {
        state.inputTracking.pendingSmartSpace = false
        actions.deleteBackward()
        state.inputTracking.recordAction(.other)
        state.inputTracking.touchContext.recordNonCharacter()
        actions.scheduleSideEffects()
    }

    /// One word-tier backspace tick (native's escalated hold-to-delete): removes the
    /// trailing whitespace run plus the word before it in a single visual chunk, sized from
    /// the context mirror (zero XPC). Returns the number of deletions performed; always ≥ 1
    /// so a held backspace never stalls. If the mirror is shorter than the real document
    /// tail (only possible mid-burst, before the next flush re-syncs it), the tick deletes
    /// what the mirror can vouch for and the following tick continues from fresh context.
    @discardableResult
    static func commitWordBackspace(
        state: QWERTYKeyboardState,
        actions: KeyboardActions
    ) -> Int {
        state.inputTracking.pendingSmartSpace = false
        let chunk = wordDeletionChunk(
            context: state.inputTracking.contextMirror.lastCharacters(TypingContextMirror.capacity))
        for _ in 0..<chunk { actions.deleteBackward() }
        state.inputTracking.recordAction(.other)
        state.inputTracking.touchContext.recordNonCharacter()
        actions.scheduleSideEffects()
        return chunk
    }

    /// Number of `Character`s (grapheme-safe — emoji count as one deleteBackward each) one
    /// word-tier tick removes: the trailing whitespace/newline run, then the non-whitespace
    /// run before it, clamped to [1, 30] so a pathological chunk can't monopolize the main
    /// thread with XPC deletes. Pure — self-testable with a String; the runtime passes the
    /// mirror's character slice.
    static func wordDeletionChunk<Context: BidirectionalCollection>(context: Context) -> Int
    where Context.Element == Character {
        guard !context.isEmpty else { return 1 }
        var count = 0
        var idx = context.endIndex
        while idx > context.startIndex {
            let prev = context.index(before: idx)
            if context[prev].isWhitespace || context[prev].isNewline {
                count += 1
                idx = prev
            } else {
                break
            }
        }
        while idx > context.startIndex {
            let prev = context.index(before: idx)
            if !(context[prev].isWhitespace || context[prev].isNewline) {
                count += 1
                idx = prev
            } else {
                break
            }
        }
        return min(max(count, 1), 30)
    }

    /// Commit return.
    static func commitReturn(
        state: QWERTYKeyboardState,
        actions: KeyboardActions
    ) {
        state.inputTracking.pendingSmartSpace = false
        actions.insertText("\n")
        state.inputTracking.recordAction(.other)
        state.inputTracking.touchContext.recordNonCharacter()

        // Same auto-return-to-letters behavior as space, matching native iOS.
        if state.currentPage != .letters {
            state.currentPage = .letters
        }

        actions.scheduleSideEffects()
    }

    /// Switch page (letters / numbers / symbols).
    static func commitModeChange(
        to page: KeyboardPage,
        state: QWERTYKeyboardState,
        actions: KeyboardActions? = nil
    ) {
        state.inputTracking.pendingSmartSpace = false
        if state.currentPage != page {
            state.currentPage = page
        }
    }

    // MARK: - Smart Punctuation

    /// Run en-US smart-punctuation transforms based on what was just inserted (already
    /// appended to the mirror). Modifies the document by `deleteBackward` + `insertText`
    /// to swap straight characters for typographic ones.
    ///
    /// Returns `true` if it mutated the document. Early-returns unless the inserted
    /// character can actually trigger a transform; the four trigger characters inspect at
    /// most four trailing mirror characters, so the letter path and the trigger path both
    /// cost zero XPC.
    @discardableResult
    private static func applySmartPunctuation(
        justInserted: String,
        traits: HostInputTraits,
        state: QWERTYKeyboardState,
        actions: KeyboardActions
    ) -> Bool {
        let mirror = state.inputTracking.contextMirror
        switch justInserted {
        case "-" where traits.smartDashesEnabled:
            // `--` → em-dash. Only fire on the SECOND `-` (i.e. the trailing two chars are `--`,
            // and the char before that — if any — is NOT a `-` so we don't keep collapsing).
            guard mirror.character(fromEnd: 1) == "-", mirror.character(fromEnd: 2) != "-" else {
                return false
            }
            actions.deleteBackward()
            actions.deleteBackward()
            actions.insertText("\u{2014}")  // —
            return true
        case "." where traits.smartDashesEnabled:
            // `...` → ellipsis. Same single-fire guard.
            guard mirror.character(fromEnd: 1) == ".", mirror.character(fromEnd: 2) == ".",
                  mirror.character(fromEnd: 3) != "." else {
                return false
            }
            actions.deleteBackward()
            actions.deleteBackward()
            actions.deleteBackward()
            actions.insertText("\u{2026}")  // …
            return true
        case "\"" where traits.smartQuotesEnabled:
            replaceJustInsertedQuote(mirror: mirror, open: "\u{201C}", close: "\u{201D}", actions: actions)
            return true
        case "'" where traits.smartQuotesEnabled:
            replaceJustInsertedQuote(mirror: mirror, open: "\u{2018}", close: "\u{2019}", actions: actions)
            return true
        default:
            return false
        }
    }

    /// Replace the just-inserted straight quote (last mirrored character) with the right
    /// typographic variant. Alternation rule: if the character immediately before the
    /// quote is whitespace, newline, an opening bracket/quote, or absent (start of doc),
    /// use the opening quote; otherwise use the closing quote.
    private static func replaceJustInsertedQuote(
        mirror: TypingContextMirror,
        open: String,
        close: String,
        actions: KeyboardActions
    ) {
        let useOpening: Bool
        if let priorChar = mirror.character(fromEnd: 1) {
            useOpening = priorChar.isWhitespace || priorChar.isNewline
                || priorChar == "(" || priorChar == "[" || priorChar == "{"
                || priorChar == "\u{201C}" || priorChar == "\u{2018}"
        } else {
            useOpening = true  // Start of document — definitely opening.
        }
        actions.deleteBackward()
        actions.insertText(useOpening ? open : close)
    }

    // MARK: - Auto-cap "I"

    /// If the cursor now sits right after `" i "` (or `"i "` at start of doc), replace
    /// the lone lowercase "i" with "I". Mirrors Apple's auto-cap heuristic for the English
    /// first-person pronoun. Reads the context mirror (zero XPC).
    private static func applyAutoCapitalizationOfI(state: QWERTYKeyboardState, actions: KeyboardActions) {
        let mirror = state.inputTracking.contextMirror
        // We just inserted a space, so the mirror ends with " ". Pattern: "...{word_break}i ".
        guard mirror.character(fromEnd: 0) == " ", mirror.character(fromEnd: 1) == "i" else { return }

        let isWordBoundary: Bool
        if let priorChar = mirror.character(fromEnd: 2) {
            isWordBoundary = priorChar.isWhitespace || priorChar.isNewline
                || priorChar == "(" || priorChar == "[" || priorChar == "{"
                || priorChar == "\""  || priorChar == "\u{201C}" || priorChar == "\u{2018}"
        } else {
            isWordBoundary = true  // Start of doc.
        }
        guard isWordBoundary else { return }

        // Delete " " then "i", then insert "I ".
        actions.deleteBackward()
        actions.deleteBackward()
        actions.insertText("I ")
    }
}

#if DEBUG
extension KeyboardCommitPipeline {
    /// Invariant check for the word-tier backspace chunk math. Returns violations so
    /// XCTest can assert; the runtime wrapper logs (does not crash).
    static func wordDeleteSelfTestFailures() -> [String] {
        var failures: [String] = []
        let cases: [(context: String, expected: Int, label: String)] = [
            ("hello world", 5, "plain trailing word"),
            ("hello world ", 6, "word + one trailing space"),
            ("say hi   ", 5, "word + trailing space run"),
            ("hi 👋👋", 2, "emoji graphemes count once each"),
            ("", 1, "empty context still deletes one"),
            ("   ", 3, "pure whitespace deletes the run"),
            ("line one\n", 4, "newline run + the word before it"),
            ("end.", 4, "punctuation rides with the word"),
            ("x", 1, "single char"),
            (String(repeating: "a", count: 60), 30, "clamped at 30"),
        ]
        for c in cases {
            let got = wordDeletionChunk(context: c.context)
            if got != c.expected {
                failures.append("\(c.label): wordDeletionChunk(\"\(c.context)\") = \(got), expected \(c.expected)")
            }
        }
        return failures
    }

    /// One-time runtime wrapper — logs instead of crashing, keyboard-extension safe.
    static func runWordDeleteSelfTest() {
        let failures = wordDeleteSelfTestFailures()
        if failures.isEmpty {
            NSLog("[SnipKeyboard] word-delete self-test passed")
        } else {
            for f in failures { NSLog("[SnipKeyboard] word-delete SELF-TEST FAILED: %@", f) }
        }
    }
}
#endif
