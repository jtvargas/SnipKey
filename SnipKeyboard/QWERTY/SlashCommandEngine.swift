//
//  SlashCommandEngine.swift
//  SnipKeyboard
//
//  Created by Jonathan Taveras Vargas on 2/11/26.
//

import Foundation
import SwiftUI

// MARK: - Slash Command Tracker (NOT @Observable — no view re-renders)

/// Detects `/query` patterns from textDocumentProxy context.
/// Runs on every relevant keystroke but mutates only plain properties —
/// zero SwiftUI re-renders. Only promotes to @Observable state when
/// the active/inactive status or matched query actually changes.
final class SlashCommandTracker {
    /// The trigger character that starts a slash command
    static let trigger: Character = "/"

    /// Last known active state — used to avoid redundant @Observable mutations
    private(set) var wasActive: Bool = false
    /// Last known query — used to avoid redundant @Observable mutations
    private(set) var lastQuery: String = ""

    /// Extract the slash command query from the text before the cursor.
    /// Returns nil if no active slash command is detected.
    ///
    /// Rules:
    /// - Must contain a `/` with no space between it and the cursor
    /// - The `/` must be at the start of input or preceded by a space/newline
    /// - Query is everything after the `/` up to the cursor
    func extractQuery(from context: String?) -> String? {
        guard let context = context, !context.isEmpty else { return nil }

        // Walk backwards from the end to find the trigger `/`
        // If we hit a space or newline before finding `/`, there's no active command
        var queryChars: [Character] = []
        var foundSlash = false

        for char in context.reversed() {
            if char == SlashCommandTracker.trigger {
                foundSlash = true
                break
            }
            // Space or newline terminates the search — no slash command
            if char.isWhitespace || char.isNewline {
                return nil
            }
            queryChars.append(char)
        }

        guard foundSlash else { return nil }

        // Validate: the `/` must be at start of string or preceded by whitespace
        let slashIndex = context.index(context.endIndex, offsetBy: -(queryChars.count + 1))
        if slashIndex > context.startIndex {
            let charBefore = context[context.index(before: slashIndex)]
            if !charBefore.isWhitespace && !charBefore.isNewline {
                return nil
            }
        }

        let query = String(queryChars.reversed())
        return query
    }

    /// Evaluate the current text context and determine if slash command state changed.
    /// Returns true if the @Observable state needs updating.
    func evaluate(context: String?) -> (changed: Bool, isActive: Bool, query: String) {
        let query = extractQuery(from: context)
        let isActive = query != nil
        let currentQuery = query ?? ""

        let changed = (isActive != wasActive) || (isActive && currentQuery != lastQuery)

        wasActive = isActive
        lastQuery = currentQuery

        return (changed, isActive, currentQuery)
    }

    /// Force reset (e.g., after snippet insertion or dismiss)
    func reset() {
        wasActive = false
        lastQuery = ""
    }
}

// MARK: - Slash Command State (@Observable — only view-affecting properties)

/// Holds the current slash command suggestions for the toolbar.
/// Mutations trigger toolbar re-renders, so all setters use equality guards.
@Observable
class SlashCommandState {
    /// Whether the slash command suggestion bar is visible
    var isActive: Bool = false

    /// The current query text (after the `/`)
    var query: String = ""

    /// Matched snippets to show as suggestions (capped for performance)
    var matchedSnippets: [SnippetItem] = []

    /// Maximum number of matches to keep in memory
    private static let maxResults = 10

    /// Update activation state from tracker evaluation (Phase 1 — UIKit side).
    /// Only mutates isActive/query. Snippet matching happens in Phase 2 (SwiftUI side).
    func updateActivation(isActive: Bool, query: String) {
        if self.isActive != isActive {
            self.isActive = isActive
        }
        if isActive {
            if self.query != query {
                self.query = query
            }
        } else {
            if !self.query.isEmpty {
                self.query = ""
            }
            if !matchedSnippets.isEmpty {
                matchedSnippets = []
            }
        }
    }

    /// Update matched snippets from the SwiftUI side (Phase 2 — reactive).
    /// Called by the toolbar view when isActive/query changes and @Query snippets are available.
    func updateMatches(allSnippets: [SnippetItem]) {
        guard isActive else {
            if !matchedSnippets.isEmpty { matchedSnippets = [] }
            return
        }
        let matches = Self.fuzzyMatch(query: query, snippets: allSnippets)
        let matchIDs = matches.map { $0.id }
        let currentIDs = matchedSnippets.map { $0.id }
        if matchIDs != currentIDs {
            matchedSnippets = matches
        }
    }

    /// Dismiss the slash command (e.g., user taps X or inserts a snippet)
    func dismiss() {
        if isActive {
            isActive = false
        }
        if !query.isEmpty {
            query = ""
        }
        if !matchedSnippets.isEmpty {
            matchedSnippets = []
        }
    }

    // MARK: - Fuzzy Matching

    /// Match snippets against the query string.
    /// Priority: exact prefix > word prefix > substring > character containment.
    /// Only matches text and URL snippet types. Excludes image/file types.
    static func fuzzyMatch(query: String, snippets: [SnippetItem]) -> [SnippetItem] {
        guard !query.isEmpty else {
            // Empty query after `/` — show recent snippets as suggestions
            return Array(
                snippets
                    .filter { isEligible($0) }
                    .sorted { ($0.lastTimeUsed ?? .distantPast) > ($1.lastTimeUsed ?? .distantPast) }
                    .prefix(maxResults)
            )
        }

        let lowerQuery = query.lowercased()

        // Score each eligible snippet
        var scored: [(snippet: SnippetItem, score: Int)] = []

        for snippet in snippets {
            guard isEligible(snippet) else { continue }
            guard let title = snippet.title?.lowercased(), !title.isEmpty else { continue }

            let score = matchScore(query: lowerQuery, title: title)
            if score > 0 {
                scored.append((snippet, score))
            }
        }

        // Sort by score descending, then by most recently used
        scored.sort { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            return (lhs.snippet.lastTimeUsed ?? .distantPast) > (rhs.snippet.lastTimeUsed ?? .distantPast)
        }

        return Array(scored.prefix(maxResults).map(\.snippet))
    }

    /// Check if a snippet is eligible for slash command suggestions.
    /// Only text and URL types are eligible (image/file can't be inserted inline).
    private static func isEligible(_ snippet: SnippetItem) -> Bool {
        guard let type = snippet.type else { return false }
        return type == .txt || type == .url
    }

    /// Compute a match score for a query against a title.
    /// Higher score = better match. 0 = no match.
    ///
    /// Scoring:
    /// - 100: Title starts with query (prefix match)
    /// -  80: A word in the title starts with query (word prefix)
    /// -  60: Query is a substring of the title
    /// -  40: All characters in query appear in order in the title (fuzzy)
    private static func matchScore(query: String, title: String) -> Int {
        // 1. Prefix match
        if title.hasPrefix(query) {
            return 100
        }

        // 2. Word prefix match — split title by common separators
        let words = title.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        for word in words {
            if word.hasPrefix(query) {
                return 80
            }
        }

        // 3. Substring match
        if title.contains(query) {
            return 60
        }

        // 4. Fuzzy character containment — all query chars appear in order
        var titleIndex = title.startIndex
        for queryChar in query {
            guard let found = title[titleIndex...].firstIndex(of: queryChar) else {
                return 0 // Character not found — no match
            }
            titleIndex = title.index(after: found)
        }
        return 40
    }
}

// MARK: - SwiftUI Environment Key

private struct SlashCommandStateKey: EnvironmentKey {
    static let defaultValue = SlashCommandState()
}

extension EnvironmentValues {
    var slashCommandState: SlashCommandState {
        get { self[SlashCommandStateKey.self] }
        set { self[SlashCommandStateKey.self] = newValue }
    }
}
