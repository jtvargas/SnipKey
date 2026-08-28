//
//  KeyboardSignposts.swift
//  SnipKeyboard
//
//  DEBUG-only os_signpost intervals for the keystroke hot path, visible in Instruments
//  (os_signpost instrument, subsystem "jrtv.snipkey.keyboard"). Complements
//  `KeyboardResponsivenessTelemetry`'s percentile export with trace-level timing.
//
//  Gated on the same cached `shadowLoggingEnabled` session flag as the other diagnostics
//  (set in `KeyboardGestureCoordinator.configure`); compiles to a plain passthrough in
//  RELEASE so the hot path carries zero cost in shipping builds.
//

import Foundation
import os

enum KeyboardSignposts {
    #if DEBUG
    /// Session cache of the shadow-logging flag; set once in `configure(...)`.
    nonisolated(unsafe) static var enabled = false
    private static let signposter = OSSignposter(subsystem: "jrtv.snipkey.keyboard",
                                                 category: "HotPath")
    #endif

    /// Wrap a hot-path section in a signpost interval. In RELEASE (or when disabled)
    /// this is just `body()`.
    @inline(__always)
    static func interval<T>(_ name: StaticString, _ body: () -> T) -> T {
        #if DEBUG
        guard enabled else { return body() }
        let state = signposter.beginInterval(name)
        defer { signposter.endInterval(name, state) }
        return body()
        #else
        return body()
        #endif
    }
}
