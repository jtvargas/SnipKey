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
/// - All model loading, tokenization, ranking, and UITextChecker work run on one serial
///   queue. Scheduling captures the supplied String value without tokenizing on main.
/// - Results hop back to MainActor only when their scheduled token is still current.
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

    /// Publish each latest evaluation, including unchanged candidates. The caller must
    /// validate the exact supplied context against its current mirror before display and
    /// again before acceptance; a matching suffix does not prove the context is current.
    /// Publishing every latest snapshot also recovers from an earlier result rejected
    /// by the caller because its document context moved without a new schedule.
    func schedule(context: String?, completion: @escaping @MainActor (
        _ candidates: [PredictiveCandidate], _ snapshot: PredictiveTextSnapshot
    ) -> Void) {
        currentToken &+= 1
        let myToken = currentToken
        let snapshot = context

        pendingWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self, tracker] in
            let result = tracker.evaluate(context: snapshot)
            let resultSnapshot = PredictiveTextSnapshot(contextBeforeInput: snapshot, partialWord: result.partialWord)
            Task { @MainActor [weak self] in
                guard let self, self.currentToken == myToken else { return }
                self.pendingWorkItem = nil
                completion(result.candidates, resultSnapshot)
            }
        }

        pendingWorkItem = workItem
        queue.asyncAfter(deadline: .now() + Self.debounce, execute: workItem)
    }

    /// Invalidate in-flight predictions after acceptance, host trait changes, or dismissal.
    func reset() {
        currentToken &+= 1
        pendingWorkItem?.cancel()
        pendingWorkItem = nil
    }
}
