//
//  ModelContainerProvider.swift
//  SnipKeyboard
//
//  Async-init wrapper for the shared SwiftData container.
//  Keeps the keyboard extension's first paint independent of SQLite/CloudKit setup.
//

import Foundation
import SwiftData

/// Shared async provider for the SwiftData `ModelContainer`.
///
/// The container is built on a detached background task during `warmup()` and cached
/// on the actor. Callers `await get()` to retrieve it. If `warmup()` was called early
/// (e.g. from `KeyboardViewController.init`), `get()` typically returns instantly
/// because the work has already finished by the time the SwiftUI view renders.
///
/// Falls back to synchronous construction if the async task is still pending and
/// the caller needs the container immediately — but the SwiftUI path should always
/// await asynchronously to keep first paint instant.
actor ModelContainerProvider {

    static let shared = ModelContainerProvider()

    private var cached: ModelContainer?
    private var pendingTask: Task<ModelContainer, Error>?

    private init() {}

    /// Kick off background creation. Safe to call multiple times — subsequent calls are no-ops.
    /// Uses a non-detached `Task` so it inherits priority from the caller (typically userInitiated
    /// from `viewDidLoad`). The actor isolates `cached`/`pendingTask`; the SQLite work itself
    /// happens inside `SnipKeyDataManager.makeSharedContainerAsync` which already hops off-main.
    func warmup() {
        if cached != nil || pendingTask != nil { return }
        pendingTask = Task {
            try await SnipKeyDataManager.makeSharedContainerAsync()
        }
    }

    /// Retrieve the container, awaiting completion of the warmup task if needed.
    /// If neither `warmup()` nor a prior `get()` has run, starts construction now.
    func get() async -> ModelContainer {
        if let cached { return cached }
        let task: Task<ModelContainer, Error>
        if let pendingTask {
            task = pendingTask
        } else {
            task = Task {
                try await SnipKeyDataManager.makeSharedContainerAsync()
            }
            pendingTask = task
        }
        do {
            let container = try await task.value
            cached = container
            pendingTask = nil
            return container
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }
}
