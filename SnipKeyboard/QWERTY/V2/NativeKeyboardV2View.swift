//
//  NativeKeyboardV2View.swift
//  SnipKeyboard
//
//  Parent UIView for the V2 keys area: the gesture coordinator + a shared callout overlay.
//  The toolbar is composed in SwiftUI (so it keeps its @Query and Environment plumbing)
//  and stacked above this view inside the SwiftUI parent.
//

import UIKit
import SwiftUI

/// Top-level UIView for the V2 keys area (no toolbar).
final class NativeKeyboardV2View: UIView {

    private let state: QWERTYKeyboardState
    private let actions: KeyboardActions

    private let coordinator: KeyboardGestureCoordinator

    /// Tracks the last-pushed values so we can skip redundant renderer work even when
    /// `withObservationTracking` fires for property reads that didn't materially change.
    private var lastObservedShift: ShiftState = .disabled
    private var lastObservedPage: KeyboardPage = .letters
    private var lastObservedAppearance: KeyboardAppearanceMode = .light
    private var lastObservedReturnLabel: String = "return"
    private var lastObservedReturnProminent: Bool = false

    init(state: QWERTYKeyboardState, actions: KeyboardActions) {
        self.state = state
        self.actions = actions
        // Callout view comes from the controller via `actions.v2CalloutView`. The coordinator
        // converts hit-test rects from its own coordinate space into root-view coords before
        // calling `show(...)`, so this view does NOT host the callout as a subview.
        self.coordinator = KeyboardGestureCoordinator(
            state: state,
            calloutView: actions.v2CalloutView ?? KeyboardCalloutView()
        )
        super.init(frame: .zero)
        backgroundColor = .clear
        setupSubviews()
        wireActions()
        beginObservingState()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    private func setupSubviews() {
        coordinator.translatesAutoresizingMaskIntoConstraints = false
        addSubview(coordinator)
        NSLayoutConstraint.activate([
            coordinator.topAnchor.constraint(equalTo: topAnchor),
            coordinator.leadingAnchor.constraint(equalTo: leadingAnchor),
            coordinator.trailingAnchor.constraint(equalTo: trailingAnchor),
            coordinator.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    private func wireActions() {
        // Reuse the controller's already-resolved width (window-scene aware); the coordinator
        // re-derives dims from `bounds` in layoutSubviews, so this is only a bootstrap.
        let dims = KeyboardDimensions(screenWidth: actions.screenWidth)
        coordinator.configure(actions: actions, dims: dims)
        coordinator.setPage(state.currentPage)
        coordinator.setAppearance(isDark: state.appearanceMode == .dark)
        coordinator.setShiftState(state.shiftState)
        coordinator.setReturnKey(label: state.returnKeyLabel, prominent: state.returnKeyIsProminent)
        coordinator.adjustCaret = { _ in
            // No-op fallback; the controller injects a real implementation via setCaretAdjustment.
        }
    }

    /// Inject the caret-adjustment closure (provided by the controller, since it owns textDocumentProxy).
    func setCaretAdjustment(_ block: @escaping (Int) -> Void) {
        coordinator.adjustCaret = block
    }

    // MARK: - Observation

    /// Subscribe to @Observable state mutations. `withObservationTracking` only fires once
    /// per registration, so we re-register inside the `onChange` callback to keep listening.
    /// This catches state changes originating from inside the UIKit coordinator
    /// (e.g. mode-change on `123` tap) — the polling-in-layoutSubviews approach missed those.
    private func beginObservingState() {
        withObservationTracking {
            _ = state.currentPage
            _ = state.shiftState
            _ = state.appearanceMode
            _ = state.returnKeyLabel
            _ = state.returnKeyIsProminent
        } onChange: { [weak self] in
            // onChange fires on whichever thread mutated the property. All our writers are main.
            Task { @MainActor [weak self] in
                self?.syncFromState()
                self?.beginObservingState()
            }
        }
    }

    /// Push @Observable state changes into the renderer. Idempotent — only diffs trigger work.
    func syncFromState() {
        if state.currentPage != lastObservedPage {
            lastObservedPage = state.currentPage
            coordinator.setPage(state.currentPage)
        }
        if state.appearanceMode != lastObservedAppearance {
            lastObservedAppearance = state.appearanceMode
            coordinator.setAppearance(isDark: state.appearanceMode == .dark)
        }
        if state.shiftState != lastObservedShift {
            lastObservedShift = state.shiftState
            coordinator.setShiftState(state.shiftState)
        }
        if state.returnKeyLabel != lastObservedReturnLabel || state.returnKeyIsProminent != lastObservedReturnProminent {
            lastObservedReturnLabel = state.returnKeyLabel
            lastObservedReturnProminent = state.returnKeyIsProminent
            coordinator.setReturnKey(label: state.returnKeyLabel, prominent: state.returnKeyIsProminent)
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Initial sync after layout; subsequent changes flow through withObservationTracking.
        syncFromState()
    }
}

// MARK: - SwiftUI Bridge

/// `UIViewRepresentable` so the V2 keys area can slot into `KeyboardViewExt.body`.
/// The toolbar is rendered separately in SwiftUI so it keeps its @Query and Environment plumbing.
struct NativeKeyboardV2KeysRepresentable: UIViewRepresentable {
    let state: QWERTYKeyboardState
    let actions: KeyboardActions
    /// Optional caret-adjustment hook from the controller (used by space-bar cursor mode).
    let adjustCaret: (Int) -> Void

    func makeUIView(context: Context) -> NativeKeyboardV2View {
        let view = NativeKeyboardV2View(state: state, actions: actions)
        view.setCaretAdjustment(adjustCaret)
        return view
    }

    func updateUIView(_ uiView: NativeKeyboardV2View, context: Context) {
        uiView.syncFromState()
        uiView.setCaretAdjustment(adjustCaret)
    }
}

/// V2 keyboard TOOLBAR for embedding in `KeyboardViewExt`. The keys area is NOT rendered
/// here — it's a pure-UIKit `NativeKeyboardV2View` mounted directly on the input-view root
/// by `KeyboardViewController` (so keys-area touches bypass SwiftUI hit-testing, eliminating
/// dead zones between keys). This view only paints the toolbar at the top and leaves the keys
/// region clear, where the UIKit keys view sits on top in z-order.
struct NativeKeyboardV2View_SwiftUI: View {
    @Environment(QWERTYKeyboardState.self) private var state
    @Environment(\.keyboardActions) private var actions
    /// Unused now that the keys live in the directly-mounted UIKit view (which receives its
    /// caret-adjust closure straight from the controller). Kept for call-site compatibility.
    let adjustCaret: (Int) -> Void

    /// Derived once from `actions.screenWidth` — the controller already owns the canonical
    /// screen width and updates it on rotation. Body re-evals reuse this without
    /// re-instantiating `KeyboardDimensions`.
    private var dims: KeyboardDimensions {
        KeyboardDimensions(screenWidth: actions.screenWidth)
    }

    var body: some View {
        VStack(spacing: 0) {
            KeyboardToolbarView(dimensions: dims)
                .frame(height: dims.toolbarHeight)
            // Keys area is owned by the UIKit `NativeKeyboardV2View` mounted on the root.
            Spacer(minLength: 0)
        }
        .frame(height: dims.totalHeight)
    }
}
