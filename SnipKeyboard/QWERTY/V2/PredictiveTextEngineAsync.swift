//
//  PredictiveTextEngineAsync.swift
//  SnipKeyboard
//
//  Serial background wrapper around PredictiveTextTracker so UITextChecker work
//  runs off the main thread without racing the tracker's mutable caches. The press → insert
//  path stays synchronous; suggestions update ~40–70ms after a typing pause.
//

import Foundation
import UIKit

/// Debounced, coalescing engine that evaluates predictive text off the main thread.
///
/// Why: `UITextChecker.completions/rangeOfMisspelledWord/guesses` each cost 10–40ms.
/// Running them synchronously on every keystroke is the dominant per-keystroke main-thread
/// cost. Moving them to a background `Task` removes that cost entirely from the press→insert
/// path.
///
/// Threading model:
/// - The engine is `@MainActor`-isolated so `schedule(context:completion:)` and the token
///   bookkeeping cannot race.
/// - The heavy `tracker.evaluate(context:)` work runs on one serial queue. This preserves
///   `PredictiveTextTracker`'s cached state while keeping `UITextChecker` off the main actor.
/// - Results hop back to `MainActor` only when the scheduled token is still current.
@MainActor
final class PredictiveTextEngineAsync {

    private let tracker = PredictiveTextTracker()
    private let queue = DispatchQueue(label: "jrtv.snipkey.predictive-text", qos: .userInitiated)

    /// Monotonic token. Each `schedule` increments it; the background task only publishes
    /// if `currentToken` is still its own token when finished.
    private var currentToken: UInt64 = 0

    /// In-flight item; cancelled when a new schedule arrives during the debounce window.
    private var pendingWorkItem: DispatchWorkItem?

    /// Debounce window before evaluation runs. 40ms coalesces typical typing bursts
    /// (~10 keys/sec) without making suggestions feel laggy.
    private static let debounce: DispatchTimeInterval = .milliseconds(40)

    private var cachedLexicon: UILexicon?

    /// Forward the system-provided supplementary lexicon (contacts / shortcuts).
    var lexicon: UILexicon? {
        get { cachedLexicon }
        set {
            cachedLexicon = newValue
            queue.async { [tracker] in
                tracker.lexicon = newValue
            }
        }
    }

    /// Schedule a predictive-text evaluation for the given context.
    /// Fires `completion` on the main actor with the new suggestions when this scheduled call
    /// is still the latest and the result has changed.
    func schedule(context: String?, completion: @escaping @MainActor (_ candidates: [PredictiveCandidate], _ partialWord: String) -> Void) {
        currentToken &+= 1
        let myToken = currentToken
        let snapshot = context

        pendingWorkItem?.cancel()
        var workItem: DispatchWorkItem!
        workItem = DispatchWorkItem { [weak self, tracker] in
            guard !workItem.isCancelled else { return }
            let result = tracker.evaluate(context: snapshot)
            Task { @MainActor [weak self] in
                guard let self, self.currentToken == myToken else { return }
                guard self.pendingWorkItem === workItem else { return }
                if result.changed {
                    completion(result.candidates, result.partialWord)
                }
            }
        }

        pendingWorkItem = workItem
        queue.asyncAfter(deadline: .now() + Self.debounce, execute: workItem)
    }

    /// Reset the cached "last suggestions" state. Use after suggestion selection
    /// so the next keystroke is treated as a fresh sequence.
    func reset() {
        currentToken &+= 1
        pendingWorkItem?.cancel()
        pendingWorkItem = nil
        queue.async { [tracker] in tracker.reset() }
    }
}
