//
//  PredictiveTextEngineAsync.swift
//  SnipKeyboard
//
//  Structured-concurrency wrapper around PredictiveTextTracker so UITextChecker work
//  runs off the main thread. The press → insert path stays synchronous; suggestions
//  update ~40–70ms after a typing pause.
//

import Foundation
import UIKit

/// Async, debounced, coalescing engine that evaluates predictive text off the main thread.
///
/// Why: `UITextChecker.completions/rangeOfMisspelledWord/guesses` each cost 10–40ms.
/// Running them synchronously on every keystroke is the dominant per-keystroke main-thread
/// cost. Moving them to a background `Task` removes that cost entirely from the press→insert
/// path.
///
/// Threading model:
/// - The engine is `@MainActor`-isolated so `schedule(context:completion:)` and the token
///   bookkeeping cannot race.
/// - The heavy `tracker.evaluate(context:)` work runs inside a non-isolated `Task` body
///   (Swift's structured concurrency dispatches it off the main actor).
/// - Results are posted back to main via `await MainActor.run { … }` only when the call
///   that scheduled them is still the latest.
@MainActor
final class PredictiveTextEngineAsync {

    private let tracker = PredictiveTextTracker()

    /// Monotonic token. Each `schedule` increments it; the background task only publishes
    /// if `currentToken` is still its own token when finished.
    private var currentToken: UInt64 = 0

    /// In-flight task; cancelled when a new schedule arrives during the debounce window.
    private var pendingTask: Task<Void, Never>?

    /// Debounce window before evaluation runs. 40ms coalesces typical typing bursts
    /// (~10 keys/sec) without making suggestions feel laggy.
    private static let debounce: Duration = .milliseconds(40)

    /// Forward the system-provided supplementary lexicon (contacts / shortcuts).
    var lexicon: UILexicon? {
        get { tracker.lexicon }
        set { tracker.lexicon = newValue }
    }

    /// Schedule a predictive-text evaluation for the given context.
    /// Fires `completion` on the main actor with the new suggestions when this scheduled call
    /// is still the latest and the result has changed.
    func schedule(context: String?, completion: @escaping @MainActor (_ suggestions: [String], _ partialWord: String) -> Void) {
        currentToken &+= 1
        let myToken = currentToken
        let snapshot = context

        pendingTask?.cancel()
        pendingTask = Task { [weak self, tracker = self.tracker] in
            try? await Task.sleep(for: Self.debounce)
            if Task.isCancelled { return }

            // Heavy UITextChecker work — runs off the main actor automatically because
            // `Task {}` inherits priority but not actor isolation when the body is non-isolated.
            // We capture `tracker` directly so the closure is `Sendable` w.r.t. self.
            let result = await Self.evaluateOffMain(tracker: tracker, context: snapshot)

            await MainActor.run {
                guard let self else { return }
                guard self.currentToken == myToken else { return }
                if result.changed {
                    completion(result.suggestions, result.partialWord)
                }
            }
        }
    }

    /// Off-actor wrapper around `tracker.evaluate(context:)`. Marked `nonisolated` so the
    /// compiler doesn't hop back to MainActor before calling — UITextChecker is thread-safe.
    private nonisolated static func evaluateOffMain(
        tracker: PredictiveTextTracker,
        context: String?
    ) async -> (changed: Bool, suggestions: [String], partialWord: String) {
        // Hop to a background task to ensure we're not on main even if the caller is.
        await Task.detached(priority: .userInitiated) {
            tracker.evaluate(context: context)
        }.value
    }

    /// Reset the cached "last suggestions" state. Use after suggestion selection
    /// so the next keystroke is treated as a fresh sequence.
    func reset() {
        pendingTask?.cancel()
        pendingTask = nil
        tracker.reset()
    }
}
