//
//  KeyboardCommitPipeline.swift
//  SnipKeyboard
//
//  Shared post-key-press side effects. Used by the V2 gesture coordinator;
//  the V1 KeyButtonView calls into the same helpers indirectly via KeyboardActions
//  so that auto-period and predictive triggers stay consistent across paths.
//
//  Smart-punctuation and auto-cap-"i" transforms (Phase E) run AFTER `insertText`
//  but BEFORE slash/predictive evaluation so the latter see the final text.
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
        actions.clearPendingPredictiveCorrection()

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

        // `insertCharacter` marks the host's synchronous textDidChange re-entrancy as
        // our own insert, so the controller skips the redundant auto-cap context read.
        actions.insertCharacter(textToInsert)
        state.inputTracking.recordAction(.character)
        if let scalar = textToInsert.first {
            state.inputTracking.touchContext.recordCharacter(scalar)
        }
        state.handleShiftAfterCharacter()

        // Smart-punctuation transforms — only run if the host field allows them.
        let traits = actions.inputTraits()
        if traits.allowsSmartTransforms {
            applySmartPunctuation(justInserted: textToInsert, traits: traits, actions: actions)
        }

        // Defer slash + predictive evaluation off the synchronous touch path. The
        // coalesced flush reads context once (post-mutation, always fresh).
        actions.scheduleSideEffects()
    }

    /// Commit space. Inserts auto-period (". ") if the previous keystrokes were
    /// character + space + space. Otherwise inserts a normal space.
    static func commitSpace(
        state: QWERTYKeyboardState,
        actions: KeyboardActions
    ) {
        let didApplyCorrection = actions.applyPendingPredictiveCorrection()
        if !didApplyCorrection {
            actions.clearPendingPredictiveCorrection()
        }

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
            applyAutoCapitalizationOfI(actions: actions)
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
        if actions.revertLastPredictiveCorrection() {
            state.inputTracking.recordAction(.other)
            state.inputTracking.touchContext.recordNonCharacter()
            actions.scheduleSideEffects()
            return
        }
        actions.deleteBackward()
        state.inputTracking.recordAction(.other)
        state.inputTracking.touchContext.recordNonCharacter()
        actions.scheduleSideEffects()
    }

    /// Commit return.
    static func commitReturn(
        state: QWERTYKeyboardState,
        actions: KeyboardActions
    ) {
        actions.clearPendingPredictiveCorrection()
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
        actions?.clearPendingPredictiveCorrection()
        state.inputTracking.pendingSmartSpace = false
        if state.currentPage != page {
            state.currentPage = page
        }
    }

    // MARK: - Smart Punctuation

    /// Run en-US smart-punctuation transforms based on what was just inserted.
    /// Operates on `documentContextBeforeInput` snapshots — modifies the document by
    /// `deleteBackward` + `insertText` to swap straight characters for typographic ones.
    ///
    /// Returns `true` if it mutated the document. Early-returns BEFORE reading the
    /// (cross-process) context unless the inserted character can actually trigger a
    /// transform — so plain letters do zero context reads on the hot path.
    @discardableResult
    private static func applySmartPunctuation(
        justInserted: String,
        traits: HostInputTraits,
        actions: KeyboardActions
    ) -> Bool {
        // Only these four characters can trigger a smart-punctuation transform.
        // Skipping the context read for everything else keeps the letter path read-free.
        switch justInserted {
        case "-", ".", "\"", "'":
            break
        default:
            return false
        }
        guard let context = actions.documentContextBeforeInput(), !context.isEmpty else { return false }

        switch justInserted {
        case "-" where traits.smartDashesEnabled:
            // `--` → em-dash. Only fire on the SECOND `-` (i.e. the trailing two chars are `--`,
            // and the char before that — if any — is NOT a `-` so we don't keep collapsing).
            if context.hasSuffix("--") {
                let beforeDashes = context.dropLast(2)
                if beforeDashes.last != "-" {
                    actions.deleteBackward()
                    actions.deleteBackward()
                    actions.insertText("\u{2014}")  // —
                    return true
                }
            }
            return false
        case "." where traits.smartDashesEnabled:
            // `...` → ellipsis. Same single-fire guard.
            if context.hasSuffix("...") {
                let beforeDots = context.dropLast(3)
                if beforeDots.last != "." {
                    actions.deleteBackward()
                    actions.deleteBackward()
                    actions.deleteBackward()
                    actions.insertText("\u{2026}")  // …
                    return true
                }
            }
            return false
        case "\"" where traits.smartQuotesEnabled:
            replaceJustInsertedQuote(context: context, open: "\u{201C}", close: "\u{201D}", actions: actions)
            return true
        case "'" where traits.smartQuotesEnabled:
            replaceJustInsertedQuote(context: context, open: "\u{2018}", close: "\u{2019}", actions: actions)
            return true
        default:
            return false
        }
    }

    /// Replace the just-inserted straight quote (last char of `context`) with the right
    /// typographic variant. Uses an alternation rule: if the character immediately before
    /// the quote is whitespace, newline, an opening bracket, or empty (start of doc), use
    /// the opening quote; otherwise use the closing quote.
    private static func replaceJustInsertedQuote(
        context: String,
        open: String,
        close: String,
        actions: KeyboardActions
    ) {
        // Strip the just-inserted straight quote from the end to examine what came before.
        let beforeQuote = context.dropLast()
        let useOpening: Bool
        if let priorChar = beforeQuote.last {
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
    /// first-person pronoun.
    private static func applyAutoCapitalizationOfI(actions: KeyboardActions) {
        guard let context = actions.documentContextBeforeInput() else { return }
        // We just inserted a space, so the context ends with " ". Pattern: "...{word_break}i ".
        guard context.hasSuffix("i ") else { return }
        let withoutTrailingSpace = context.dropLast()        // "...i"
        let beforeI = withoutTrailingSpace.dropLast()        // "..."

        let isWordBoundary: Bool
        if let priorChar = beforeI.last {
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
