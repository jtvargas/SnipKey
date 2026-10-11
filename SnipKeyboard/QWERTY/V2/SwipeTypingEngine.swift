//
//  SwipeTypingEngine.swift
//  SnipKeyboard
//
//  Process-wide owner of the swipe lexicon + decoder. `prepare()` loads the bundled English
//  lexicon on a utility queue during the controller's deferred setup; `decode` is
//  synchronous on the caller's thread so commits stay ordered with subsequent taps.
//  Callers gate gesture capture on `isReady`; before preparation completes, ordinary
//  tapping remains available and `decode` returns no candidates.
//

import Foundation
import os

final class SwipeTypingEngine: @unchecked Sendable {

    static let shared = SwipeTypingEngine()

    private let decoderLock = OSAllocatedUnfairLock<SwipeDecoder?>(initialState: nil)
    private let loadQueue = DispatchQueue(label: "com.snipkey.swipe.load", qos: .utility)
    private var loadRequested = false

    private init() {}

    /// Kick off the one-time lexicon load. Safe to call repeatedly.
    func prepare() {
        loadQueue.async { [self] in
            guard !loadRequested else { return }
            loadRequested = true
            guard let lexicon = SwipeLexicon.sharedForSuggestionsAndSwipe else {
                NSLog("[SnipKeyboard] swipe lexicon missing — swipe typing disabled")
                return
            }
            let decoder = SwipeDecoder(lexicon: lexicon)
            decoderLock.withLock { $0 = decoder }
        }
    }

    var isReady: Bool {
        decoderLock.withLock { $0 != nil }
    }

    /// Rank candidate words for a finished trace. Empty until `prepare()` has completed.
    func decode(_ trace: [SwipeTracePoint], layout: SwipeKeyLayout, maxCandidates: Int = 3) -> [SwipeCandidate] {
        guard let decoder = decoderLock.withLock({ $0 }) else { return [] }
        return decoder.decode(trace, layout: layout, maxCandidates: maxCandidates)
    }
}
