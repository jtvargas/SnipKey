//
//  KeyboardViewController.swift
//  SnipKeyboard
//
//  Created by Jonathan Taveras Vargas on 3/31/24.
//

import UIKit
import SwiftUI
import SwiftData

import MobileCoreServices
import UniformTypeIdentifiers

/// Protocol matching UIApplication.open(_:options:completionHandler:).
/// Declared at file scope so the ObjC runtime registers it globally,
/// enabling dynamic conformance checking via `as?` against UIApplication.
/// This is the standard approach used by major third-party keyboards (Gboard, SwiftKey).
@objc protocol KeyboardExtensionOpenURL {
    @objc func open(_ url: URL, options: [String: Any], completionHandler: ((Bool) -> Void)?)
}

class KeyboardViewController: UIInputViewController {
    
    @IBOutlet var nextKeyboardButton: UIButton!
    
    var isLongPressing = false
    var deletionCount = 0
    
    // MARK: - QWERTY Keyboard State & Actions
    
    /// Shared state for the QWERTY keyboard, injected into SwiftUI environment
    let qwertyState = QWERTYKeyboardState()
    
    /// Height constraint for the keyboard extension input view
    private var heightConstraint: NSLayoutConstraint?
    
    /// Track last known screen width to avoid redundant updateQWERTYState() calls from viewWillLayoutSubviews
    private var lastKnownWidth: CGFloat = 0
    /// V2 callout overlay — mounted on the root view so it can overlap the toolbar and
    /// draw above the top row of keys.
    private let v2CalloutView = KeyboardCalloutView()

    /// V2 keys area, mounted as a DIRECT UIKit child of the input view (not inside the
    /// SwiftUI host). Keeping the keys in pure UIKit — like the native/Grammarly keyboard —
    /// means keys-area touches bypass SwiftUI's event-aware hit-testing entirely, so there
    /// are no dead zones between keys. Only created when V2 is enabled.
    private var nativeV2KeysView: NativeKeyboardV2View?
    private var emojiKeyboardView: EmojiKeyboardView?
    private var emojiSearchActive = false
    private lazy var inlineEmojiRecents = EmojiRecentsStore()
    private var predictionContext: String?
    
    // MARK: - Slash Command
    
    /// Slash command detection — plain class, zero SwiftUI re-renders per keystroke.
    /// Only promotes to @Observable state when the active/query status actually changes.
    private let slashCommandTracker = SlashCommandTracker()
    
    /// Observable slash command state — shared with SwiftUI toolbar for suggestions display.
    let slashCommandState = SlashCommandState()
    
    // MARK: - Predictive Text

    /// Async predictive text engine — `UITextChecker` work runs on a serial background
    /// queue, debounced 40ms and coalesced. The press→insert path never blocks on it.
    private let predictiveEngineAsync = PredictiveTextEngineAsync()

    /// Observable predictive text state — shared with SwiftUI toolbar for suggestions display.
    let predictiveTextState = PredictiveTextState()

    // MARK: - NLP Reminders

    /// Observable reminder state — drives the "Create reminder" pill when the user types
    /// `/remind … at <time>`. Updated from the coalesced side-effect flush. See ReminderParseEngine.
    let reminderSuggestionState = ReminderSuggestionState()

    /// Observable timer state — drives the "Create timer" pill when the user types `/timer <dur>`.
    /// Updated from the coalesced side-effect flush, gated on the Timer integration. See TimerParseEngine.
    let timerSuggestionState = TimerSuggestionState()

    // MARK: - Clipboard Paste

    /// Observable clipboard availability — drives the toolbar paste button. Refreshed in
    /// `viewWillAppear` and by `clipboardPollTimer` while the keyboard is visible.
    let clipboardState = ClipboardState()

    /// 1s metadata-only poll (changeCount, then hasStrings/hasURLs only when it moved) so the
    /// paste button appears live when the user copies text while the keyboard stays open.
    /// Visibility-scoped: started by `performDeferredSetup` (first appearance, after the first
    /// frame) and `viewWillAppear` thereafter, invalidated in `viewWillDisappear`.
    private var clipboardPollTimer: Timer?

    // MARK: - Reminder destination (Integrations)

    /// Active reminder destination + integration enable flag. Read ONCE per session in
    /// `performDeferredSetup` (never per keystroke), mirroring how every other App Group setting
    /// is read. A change in the host app takes effect the next time the keyboard is loaded — same
    /// semantics as the V2/hit-resolver toggles. See INTEGRATIONS.md.
    private var remindersIntegrationEnabled = false
    private var reminderDestination: ReminderDestination = .snipKey

    /// Whether the Timer integration is enabled. Read ONCE per session in `performDeferredSetup`.
    /// When false, `/timer` is inert (no pill). See INTEGRATIONS.md.
    private var timerIntegrationEnabled = false

    /// Cached once per keyboard session. Avoids App Group UserDefaults reads from space,
    /// auto-cap, and text-change paths while the user is actively typing.
    private var autoCapitalizationEnabled = true

    /// Cached host field input traits (keyboard type/appearance, return key, autocap,
    /// autocorrect/spell/smart-punctuation flags, globe key, locale codes). These are
    /// properties of the focused text field — constant while typing in one field — but each
    /// backing `textDocumentProxy` read is a cross-process XPC call. The keystroke path only
    /// ever reads this cache; `refreshHostInputTraits` refreshes it off that path
    /// (`viewDidLoad`, `viewWillAppear`, external `textDidChange`, the coalesced
    /// `flushSideEffects`, and input-mode changes).
    private var cachedHostInputTraits: HostInputTraits = .defaults

    /// Cached keyboard screen width. Resolved off the hot path (`viewDidLoad` / rotation) so the
    /// SwiftUI toolbar's `dims` computed properties don't walk the window/scene graph on every
    /// body re-evaluation. Still rotation/Stage-Manager correct via `viewWillTransition`.
    private var cachedScreenWidth: CGFloat = 393

    // MARK: - Hot-path coalescing (V2)

    /// True while one of our own proxy mutations (insert, delete, or caret adjustment) is
    /// executing. Synchronous text/selection callbacks are echoes, not external edits;
    /// they must not cancel an active press or space-bar cursor drag.
    private var ownMutationInFlight = false

    /// Uptime of the last own mutation. Some hosts deliver `textDidChange` for our own write
    /// on a later runloop turn instead of synchronously; a change arriving within
    /// `ownMutationEchoWindow` of our write is treated as that echo (no host reads — the
    /// coalesced flush already scheduled by the commit resyncs the mirror on the next turn).
    private var lastOwnMutationUptime: TimeInterval = 0
    private static let ownMutationEchoWindow: TimeInterval = 0.05

    /// Whether a `textDidChange` is attributable to our own write (synchronous or late echo).
    private var textDidChangeIsOwnEcho: Bool {
        ownMutationInFlight
            || ProcessInfo.processInfo.systemUptime - lastOwnMutationUptime < Self.ownMutationEchoWindow
    }

    /// Coalescer guard: ensures at most one deferred side-effect flush is queued per runloop.
    /// V2 commits schedule slash + predictive evaluation here instead of running them
    /// synchronously inside `touchesBegan`, so a fast burst collapses to one context read
    /// (and one slash/predictive pass) per frame.
    private var sideEffectFlushScheduled = false

    /// Coalescer guard for `scheduleTypingContextResync` (selection-driven mirror re-sync).
    private var typingContextResyncScheduled = false

    /// Only selection callbacks need the extra selected-text host read during reconciliation.
    private var selectionContextValidationNeeded = false

    /// Prevent an already-queued side-effect flush from rearming predictions after dismissal.
    private var isKeyboardVisible = false

    /// Staged init (SwiftKey: `_perInstanceSetUp` → `_postKeyboardAppearanceSetUp`).
    /// `viewDidLoad` builds only what the first frame and first keystroke need;
    /// `performDeferredSetup` runs once, one runloop turn after the first `viewDidAppear`.
    private var didPerformDeferredSetup = false

    /// Memory warnings are logged once per session so a sustained-pressure host doesn't
    /// flood the log while the keyboard keeps typing.
    private var didLogMemoryWarning = false
    
    /// Wraps textDocumentProxy operations as closures for the SwiftUI QWERTY keyboard
    private lazy var keyboardActionsStruct: KeyboardActions = {
        KeyboardActions(
            insertText: { [weak self] text in
                self?.insertOwnText(text)
            },
            deleteBackward: { [weak self] in
                self?.deleteOwnBackward()
            },
            advanceToNextInputMode: { [weak self] in
                self?.advanceToNextInputMode()
            },
            documentContextBeforeInput: { [weak self] in
                self?.textDocumentProxy.documentContextBeforeInput
            },
            screenWidthProvider: { [weak self] in
                self?.cachedScreenWidth ?? 393
            },
            openApp: { [weak self] in
                if let url = URL(string: "snipkey://open") {
                    self?.openURL(url)
                }
            },
            hasFullAccess: { [weak self] in
                self?.hasFullAccess ?? false
            },
            createReminder: { [weak self] body, fireDate in
                guard let self = self else { return }
                // NLP `/remind … at <time>` flow: deliver at the parsed absolute time via the
                // selected destination. Scheduling requires Full Access.
                guard self.hasFullAccess else {
                    print("[Reminder] Full Access required to schedule from the keyboard")
                    return
                }
                self.routeReminder(title: "Reminder", body: body, fireDate: fireDate)
            },
            createTimer: { [weak self] duration, label in
                guard let self = self else { return }
                // Full Access is required to schedule a local notification from the keyboard.
                guard self.hasFullAccess else {
                    print("[Timer] Full Access required to create from the keyboard")
                    return
                }
                self.routeTimer(duration: duration, label: label)
            },
            pasteFromClipboard: { [weak self] in
                guard let self, self.hasFullAccess else { return }
                let pb = UIPasteboard.general
                // Content read — the one call that can trigger the iOS 16 paste prompt.
                guard let text = pb.string ?? pb.url?.absoluteString, !text.isEmpty else { return }
                self.insertOwnText(text)
                // Pasted content is arbitrary — never carries a smart space (snippet precedent).
                self.qwertyState.inputTracking.pendingSmartSpace = false
                self.scheduleSideEffectFlush()
            },
            copySnippetFile: { [weak self] snippet in
                guard let self, self.hasFullAccess else { return .noFullAccess }
                // Cheap metadata reads stay on the main actor (main-context model).
                let mimeType = snippet.file?.fileFormatType
                guard let fileID = snippet.file?.persistentModelID else { return .missingData }
                // The externalStorage blob is a disk read — fault it on a background
                // ModelContext so a multi-MB PDF never stalls the key/touch path.
                let data: Data? = await Task.detached(priority: .userInitiated) {
                    let container = await ModelContainerProvider.shared.get()
                    let context = ModelContext(container)
                    var descriptor = FetchDescriptor<SnippetFile>(
                        predicate: #Predicate { $0.persistentModelID == fileID })
                    descriptor.fetchLimit = 1
                    return (try? context.fetch(descriptor))?.first?.fileData
                }.value
                return SnippetPasteboard.copyFile(data: data, mimeType: mimeType, hasFullAccess: true)
            },
            evaluateSlashCommand: { [weak self] in
                // Toolbar path (slash trigger button): read context and evaluate synchronously.
                guard let self = self else { return }
                self.runSlashEvaluation(context: self.textDocumentProxy.documentContextBeforeInput)
            },
            evaluatePredictiveText: { [weak self] in
                // Toolbar path (predictive dismiss): read context and schedule synchronously.
                guard let self = self else { return }
                self.runPredictiveEvaluation(context: self.textDocumentProxy.documentContextBeforeInput)
            },
            scheduleSideEffects: { [weak self] in
                self?.scheduleSideEffectFlush()
            },
            adjustCaret: { [weak self] delta in
                guard let self = self, delta != 0 else { return }
                // A caret move invalidates the pending smart space — the cursor is no longer
                // right after a suggestion's trailing space, so don't eat an arbitrary space.
                self.qwertyState.inputTracking.pendingSmartSpace = false
                self.resetPredictivePipeline()
                // The context mirror tracks text BEFORE the caret: re-sync it (coalesced,
                // next turn) even for hosts that don't echo programmatic moves back through
                // `selectionDidChange`.
                self.ownMutationInFlight = true
                self.textDocumentProxy.adjustTextPosition(byCharacterOffset: delta)
                self.ownMutationInFlight = false
                self.lastOwnMutationUptime = ProcessInfo.processInfo.systemUptime
                self.scheduleTypingContextResync()
            },
            inputTraits: { [weak self] in
                self?.cachedHostInputTraits ?? .defaults
            },
            activeInputLocaleCodes: { [weak self] in
                // O(1): computed in `refreshHostInputTraits`, never on a layout pass.
                self?.cachedHostInputTraits.localeCodes ?? []
            },
            insertQuickCommand: { [weak self] command in
                self?.insertQuickCommand(command)
            },
            acceptPredictiveCandidate: { [weak self] candidate in
                self?.acceptPredictiveCandidate(candidate)
            },
            showSwipeAlternatives: { [weak self] committed, alternatives in
                self?.showSwipeAlternatives(committed: committed, alternatives: alternatives)
            },
            v2CalloutView: v2CalloutView
        )
    }()
    
    override func updateViewConstraints() {
        super.updateViewConstraints()
        
        // Add custom view sizing constraints here
    }
    
    func getSelectedText() -> String {
        if self.textDocumentProxy.hasText {
            let selectedText = self.textDocumentProxy.selectedText ?? ""
            print("has text selected \(selectedText)")
            return selectedText
        }
        
        return ""
    }
    
    
    
    /// First stage of the staged init: view hierarchy, state hydration and the App Group
    /// flag the first keystroke needs. Everything else is in `performDeferredSetup`.
    override func viewDidLoad() {
        super.viewDidLoad()

        // Kick off SwiftData container construction immediately on a background task.
        // This is first-frame work, not deferrable: `KeyboardViewExt` only mounts the
        // toolbar — and selects the typing surface so the keys view becomes visible — once
        // `ModelContainerProvider.get()` returns. Starting here (vs. SwiftUI's `.task`)
        // overlaps the ~50–200ms SQLite + CloudKit setup with our own view construction.
        Task { await ModelContainerProvider.shared.warmup() }

        // The one App Group flag the first keystroke's auto-cap decision consults.
        autoCapitalizationEnabled = AppGroupSettings.bool(
            forKey: AppGroupSettings.Key.autoCapitalizationEnabled, default: true)

        // Prime the hot-path caches once. Both are refreshed off the keystroke path afterwards
        // (traits in `viewWillAppear` / `flushSideEffects`, width in `viewWillLayoutSubviews`).
        cachedScreenWidth = keyboardScreenWidth()
        refreshHostInputTraits()

        // Perform custom UI setup here
        self.nextKeyboardButton = UIButton(type: .system)
        
        self.nextKeyboardButton.setTitle(NSLocalizedString("Next Keyboard", comment: "Title for 'Next Keyboard' button"), for: [])
        self.nextKeyboardButton.sizeToFit()
        self.nextKeyboardButton.translatesAutoresizingMaskIntoConstraints = false
        
        self.nextKeyboardButton.addTarget(self, action: #selector(handleInputModeList(from:with:)), for: .allTouchEvents)
        
        self.view.addSubview(self.nextKeyboardButton)
        
        self.nextKeyboardButton.leftAnchor.constraint(equalTo: self.view.leftAnchor).isActive = true
        self.nextKeyboardButton.bottomAnchor.constraint(equalTo: self.view.bottomAnchor).isActive = true
        
        
        // Host SwiftUI keyboard with QWERTY state and actions injected
        let contentView = UIHostingController(
            rootView: KeyboardViewExt(
                qwertyState: qwertyState,
                keyboardActions: keyboardActionsStruct,
                slashCommandState: slashCommandState,
                predictiveTextState: predictiveTextState,
                reminderSuggestionState: reminderSuggestionState,
                timerSuggestionState: timerSuggestionState,
                clipboardState: clipboardState
            )
        )
        
        contentView.view.backgroundColor = .clear

        view.addKeyboardSubview(contentView.view)

        // V2 keys area as a direct UIKit child of the input view, ABOVE the SwiftUI host but
        // BELOW the callout overlay. The SwiftUI side (`NativeKeyboardV2View_SwiftUI`)
        // renders only the toolbar; this view draws and handles touches for all the keys.
        // This removes SwiftUI's hit-testing from the keys touch path — the native model —
        // so taps in the gaps between keys always reach the gesture coordinator.
        let keysView = NativeKeyboardV2View(state: qwertyState, actions: keyboardActionsStruct)
        keysView.setCaretAdjustment(keyboardActionsStruct.adjustCaret)
        keysView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(keysView)
        let toolbarH = KeyboardDimensions(screenWidth: keyboardScreenWidth()).toolbarHeight
        NSLayoutConstraint.activate([
            keysView.topAnchor.constraint(equalTo: view.topAnchor, constant: toolbarH),
            keysView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            keysView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            keysView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        self.nativeV2KeysView = keysView
        // Hidden while the snippet grid is showing (SwiftUI renders the grid full-screen);
        // visible when the keyboard is showing. Kept in sync via observation.
        keysView.isHidden = qwertyState.surface != .typing
        observeKeyboardSurface()

        // V2 callout overlay — mounted on the root view so it can overlap the toolbar
        // and draw above the top row of keys. The V2 gesture coordinator references this
        // view through `KeyboardActions.v2CalloutView` and converts hit-test rects from
        // its own coordinate space into root-view coords before calling `show(...)`.
        v2CalloutView.translatesAutoresizingMaskIntoConstraints = true
        view.addSubview(v2CalloutView)
        
        // Set explicit height constraint so the system knows how tall the keyboard should be.
        // Without this, GeometryReader (now removed) would fail to communicate height upward.
        let desiredHeight = KeyboardDimensions.totalHeight(forScreenWidth: keyboardScreenWidth())
        let constraint = NSLayoutConstraint(
            item: self.view!,
            attribute: .height,
            relatedBy: .equal,
            toItem: nil,
            attribute: .notAnAttribute,
            multiplier: 1.0,
            constant: desiredHeight
        )
        constraint.priority = UILayoutPriority(999) // Just below .required to avoid conflicts
        self.view.addConstraint(constraint)
        self.heightConstraint = constraint
        
        // Tell the system we want to defer left/right edge system gestures (see the
        // `preferredScreenEdgesDeferringSystemGestures` override). Must be called after the
        // view hierarchy is set up; re-applied in `viewWillAppear`.
        setNeedsUpdateOfScreenEdgesDeferringSystemGestures()
    }

    // MARK: - Deferred setup (second init stage)

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !didPerformDeferredSetup else { return }
        didPerformDeferredSetup = true
        // One runloop turn later: the first frame is committed and nothing here is needed
        // before a user can possibly interact (a touch can't be processed earlier either).
        DispatchQueue.main.async { [weak self] in
            self?.performDeferredSetup()
        }
    }

    /// Everything the first frame / first keystroke does NOT need: integration flags,
    /// predictive-engine warm-up, snippet-grid notification channels, input-mode tracking
    /// and clipboard polling. Runs exactly once, after the first `viewDidAppear`.
    private func performDeferredSetup() {
        // Reminder / timer integration flags: consulted only by the coalesced flush and the
        // pill-accept paths, never per keystroke. A change in the host app takes effect the
        // next time the keyboard is loaded — same semantics as every other App Group setting.
        remindersIntegrationEnabled = AppGroupSettings.bool(
            forKey: AppGroupSettings.Key.remindersIntegrationEnabled, default: false)
        reminderDestination = ReminderDestination(appGroupRawValue: AppGroupSettings.string(
            forKey: AppGroupSettings.Key.reminderDestination,
            default: ReminderDestination.default.rawValue))
        timerIntegrationEnabled = AppGroupSettings.bool(
            forKey: AppGroupSettings.Key.timerIntegrationEnabled, default: false)

        // Predictive engine warm-up: supplementary lexicon (contacts, shortcuts).
        requestSupplementaryLexicon { [weak self] lexicon in
            self?.predictiveEngineAsync.lexicon = lexicon
        }
        nativeV2KeysView?.refreshSwipeSettings()

        // Legacy snippet-grid channels (`KeyboardView` posts these). Routed through the
        // own-mutation helpers so the context mirror stays in lockstep with the document.
        NotificationCenter.default.addObserver(forName: NSNotification.Name(rawValue: "addKey"), object: nil, queue: nil) { [weak self] notification in
            guard let self = self else { return }

            // Text-only channel: file/image snippets go through the
            // `copySnippetFile` action so the caller gets a real result.
            if let snippet = notification.object as? SnippetItem {
                self.insertOwnText(snippet.content ?? "")
            }

            if let text = notification.object as? String {
                self.insertOwnText(text)
            }
        }

        NotificationCenter.default.addObserver(forName: NSNotification.Name(rawValue: "switchKey"), object: nil, queue: nil) { [weak self] _ in
            self?.advanceToNextInputMode()
        }

        NotificationCenter.default.addObserver(
            forName: NSNotification.Name(rawValue: "deleteKey"),
            object: nil,
            queue: nil
        ) { [weak self] notification in
            if let isLongPress = notification.object as? Bool {
                self?.handleDelete(isLongPress: isLongPress)
            }
        }

        // Adding/removing keyboards in Settings changes the globe key and the space-bar
        // locale subtitle; both live in the traits cache.
        NotificationCenter.default.addObserver(
            forName: UITextInputMode.currentInputModeDidChangeNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            guard let self else { return }
            self.nativeV2KeysView?.cancelActiveInteraction()
            self.resetPredictivePipeline()
            self.refreshHostInputTraits()
            self.updateQWERTYState()
        }

        if view.window != nil {
            startClipboardPolling()
        }
    }

    // MARK: - Own proxy mutations

    /// Insert text we authored. The context mirror is advanced BEFORE the proxy call so the
    /// host's synchronous `textDidChange` re-entrancy computes auto-cap from post-insert
    /// context; `ownMutationInFlight` tells that re-entrancy to do no host reads.
    private func insertOwnText(_ text: String) {
        qwertyState.inputTracking.contextMirror.append(text)
        if !text.isEmpty, qwertyState.isDocumentEmpty {
            qwertyState.isDocumentEmpty = false
        }
        ownMutationInFlight = true
        textDocumentProxy.insertText(text)
        ownMutationInFlight = false
        lastOwnMutationUptime = ProcessInfo.processInfo.systemUptime
    }

    /// Delete one character backward, mirror first (see `insertOwnText`).
    private func deleteOwnBackward() {
        qwertyState.inputTracking.contextMirror.deleteBackward()
        ownMutationInFlight = true
        textDocumentProxy.deleteBackward()
        ownMutationInFlight = false
        lastOwnMutationUptime = ProcessInfo.processInfo.systemUptime
    }

    /// Re-sync the context mirror from one real `documentContextBeforeInput` read. Off the
    /// keystroke path only: `viewWillAppear`, external `textDidChange`, the coalesced
    /// selection re-sync below, and the flush (which reuses the returned context).
    @discardableResult
    private func resyncTypingContextFromHost() -> String? {
        let context = textDocumentProxy.documentContextBeforeInput
        let mirror = qwertyState.inputTracking.contextMirror
        // Late selection callbacks can be echoes of our own insert. Preserve swipe
        // alternatives only when the host still agrees with the replayed caret context.
        let matchesMirror = context.map {
            $0.suffix(TypingContextMirror.capacity)
                .elementsEqual(mirror.lastCharacters(TypingContextMirror.capacity))
        } ?? mirror.isEmpty
        let hasSelection = selectionContextValidationNeeded
            && textDocumentProxy.selectedText?.isEmpty == false
        selectionContextValidationNeeded = false
        if !matchesMirror || hasSelection {
            // Own caret moves also change this prefix. Interaction cancellation belongs
            // to the external callback branches, not this shared echo reconciliation.
            qwertyState.inputTracking.pendingSmartSpace = false
            resetPredictivePipeline()
        }
        mirror.reset(to: context)
        // Before-caret emptiness alone also describes the start of a populated field.
        // Read the remaining proxy facets only for an apparently empty prefix, off touch-down.
        let isEmpty = context?.isEmpty != false
            && !textDocumentProxy.hasText
            && textDocumentProxy.documentContextAfterInput?.isEmpty != false
            && textDocumentProxy.selectedText?.isEmpty != false
        if qwertyState.isDocumentEmpty != isEmpty {
            qwertyState.isDocumentEmpty = isEmpty
        }
        return context
    }

    /// Caret moves (host taps, space-bar cursor drag steps) arrive as a stream of selection
    /// callbacks; coalesce them to one read per runloop turn, and to zero when a side-effect
    /// flush — which re-syncs the mirror itself — is already queued for this turn.
    private func scheduleTypingContextResync() {
        guard !typingContextResyncScheduled, !sideEffectFlushScheduled else { return }
        typingContextResyncScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.typingContextResyncScheduled = false
            self.resyncTypingContextFromHost()
        }
    }

    //    Simulate fast deletion
    func handleDelete(isLongPress: Bool) {
        if isLongPress {
            if !isLongPressing {
                // Start of long press
                isLongPressing = true
                deletionCount = 0
            }
            
            deletionCount += 1
            let charsToDelete = min(deletionCount, 10)
            
            for _ in 0..<charsToDelete {
                deleteOwnBackward()
            }
        } else {
            // Single tap
            isLongPressing = false
            deletionCount = 0
            deleteOwnBackward()
        }
    }
    
    // MARK: - Edge gesture deferral

    /// Defer the system's left/right screen-edge pan gestures so the FIRST touch on the
    /// left/right key columns (Q/A/Z, P/L/M-area, backspace) reaches our keys immediately
    /// instead of being swallowed for ~1s by `UIScreenEdgePanGestureRecognizer`. Real-device
    /// only; validated on iOS 16–18. Paired with `setNeedsUpdateOfScreenEdgesDeferringSystemGestures()`
    /// in `viewDidLoad` / `viewWillAppear`.
    override var preferredScreenEdgesDeferringSystemGestures: UIRectEdge {
        [.left, .right]
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        isKeyboardVisible = true
        setNeedsUpdateOfScreenEdgesDeferringSystemGestures()
        nativeV2KeysView?.refreshSwipeSettings()
        resetPredictivePipeline()
        // The focused field may differ from the last appearance: one traits refresh and one
        // context read here, so the first keystroke after appearing is read-free.
        refreshHostInputTraits()
        resyncTypingContextFromHost()
        updateQWERTYState()
        // Before the deferred stage, polling starts from `performDeferredSetup` instead.
        if didPerformDeferredSetup {
            startClipboardPolling()
        }
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // iOS terminates keyboard extensions around 60–70 MB. Drop every rebuildable cache
        // (key layers / accessibility tree on the keys surface, in-flight predictions and
        // their candidate arrays) so the keyboard survives instead of vanishing mid-sentence.
        nativeV2KeysView?.handleMemoryPressure()
        resetPredictivePipeline()
        if !didLogMemoryWarning {
            didLogMemoryWarning = true
            NSLog("[SnipKeyboard] memory warning — dropped rebuildable caches")
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        isKeyboardVisible = false
        nativeV2KeysView?.cancelActiveInteraction()
        emojiKeyboardView?.cancelInteraction()
        resetPredictivePipeline()
        stopClipboardPolling()
        // Persist shadow-mode telemetry + learned per-user offsets off the hot path.
        TypingTelemetry.shared.flush()
        KeyboardResponsivenessTelemetry.shared.flush()
        TouchOffsetModel.shared.flush()
        #if DEBUG
        CalibrationCapture.shared.flush()
        #endif
    }

    // MARK: - Clipboard Polling

    private func startClipboardPolling() {
        guard hasFullAccess else { return }   // null pasteboard without Full Access — skip the XPC
        clipboardState.refresh()              // immediate refresh on appear
        guard clipboardPollTimer == nil else { return }
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.clipboardState.refresh()    // main run loop → main thread
        }
        timer.tolerance = 0.5
        RunLoop.main.add(timer, forMode: .default)  // pauses during pill scroll tracking
        clipboardPollTimer = timer
    }

    private func stopClipboardPolling() {
        clipboardPollTimer?.invalidate()
        clipboardPollTimer = nil
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        // System dark-mode toggle (or any other trait change) while the keyboard is
        // visible should re-run our appearance-mode resolution so V2's CALayer
        // renderer repaints with the new palette.
        if previousTraitCollection?.userInterfaceStyle != self.traitCollection.userInterfaceStyle {
            updateQWERTYState()
        }
    }

    /// Resolve the keyboard's screen width without the deprecated `UIScreen.main`.
    /// Prefers the view's window-scene screen (correct under Stage Manager / external
    /// displays); falls back to the laid-out view width, then a sensible bootstrap before
    /// the window is attached (viewDidLoad). The dims are re-derived from `bounds` in the
    /// coordinator's `layoutSubviews`, so this value only needs to be a reasonable bootstrap.
    private func keyboardScreenWidth() -> CGFloat {
        if let w = view.window?.windowScene?.screen.bounds.width, w > 0 { return w }
        if view.bounds.width > 0 { return view.bounds.width }
        return 393  // iPhone bootstrap before the window/scene exists.
    }

    override func viewWillLayoutSubviews() {
        self.nextKeyboardButton.isHidden = !cachedHostInputTraits.needsInputModeSwitchKey
        // Update height constraint on layout changes (rotation, different device)
        let newWidth = keyboardScreenWidth()
        // Refresh the hot-path width cache here (off the keystroke path) so SwiftUI `dims` reads
        // stay rotation/Stage-Manager correct without walking the window/scene graph per body eval.
        cachedScreenWidth = newWidth
        updateKeyboardHeight(for: newWidth)
        // Only update QWERTY state when screen width actually changed (rotation)
        // This avoids doubling observable mutations since textDidChange also calls updateQWERTYState
        if newWidth != lastKnownWidth {
            lastKnownWidth = newWidth
            updateQWERTYState()
        }
        super.viewWillLayoutSubviews()
    }

    private func updateKeyboardHeight(for width: CGFloat? = nil) {
        let base = KeyboardDimensions.totalHeight(forScreenWidth: width ?? keyboardScreenWidth())
        let extra = qwertyState.surface == .emoji && emojiSearchActive
            ? EmojiKeyboardView.searchAdditionalHeight : 0
        let height = base + extra
        guard heightConstraint?.constant != height else { return }
        heightConstraint?.constant = height
        view.setNeedsLayout()
    }
    
    /// Some hosts (WKWebView-backed fields are the known offender) report caret moves and
    /// selection edits ONLY through the selection callbacks, never `textDidChange`. The
    /// mirror tracks text BEFORE the caret, so a selection change re-syncs it (coalesced to
    /// one read per turn). Guarded so a host that echoes our own insert's caret move
    /// synchronously can't put a read back on the keystroke path.
    override func selectionDidChange(_ textInput: UITextInput?) {
        guard !ownMutationInFlight else { return }
        selectionContextValidationNeeded = true
        if !textDidChangeIsOwnEcho {
            nativeV2KeysView?.cancelActiveInteraction(commitPending: true)
            qwertyState.inputTracking.pendingSmartSpace = false
            resetPredictivePipeline()
        }
        scheduleTypingContextResync()
    }
    
    override func textDidChange(_ textInput: UITextInput?) {
        KeyboardResponsivenessTelemetry.shared.markTextDidChange()

        if textDidChangeIsOwnEcho {
            // Our own insert/delete/caret adjustment (synchronous or within the echo window).
            // Use local state here; caret adjustments schedule their mirror resync explicitly.
            updateAutoCapitalization()
            if !ownMutationInFlight {
                scheduleTypingContextResync()
            }
        } else {
            // External change, or an own echo arriving after the echo window. Preserve
            // pending taps before ending the interaction; then read the resulting context.
            nativeV2KeysView?.cancelActiveInteraction(commitPending: true)
            resetPredictivePipeline()
            refreshHostInputTraits()
            resyncTypingContextFromHost()
            updateQWERTYState()
        }
        
        // Only post selection notifications when snippet view is active.
        // These are consumed by KeyboardView's observers and serve no purpose
        // during QWERTY typing — skipping them avoids N observer calls per keystroke.
        if qwertyState.surface == .snippets {
            let selectedText = getSelectedText()
            
            if !selectedText.isEmpty{
                NotificationCenter.default.post(
                    name: NSNotification.Name(rawValue: "selectText"), object: selectedText)
            }
            
            if selectedText.isEmpty{
                NotificationCenter.default.post(
                    name: NSNotification.Name(rawValue: "selectTextEmpty"), object: nil)
            }
        }
    }
    
    // MARK: - Coalesced Side-Effects (V2)

    /// Queue a single deferred slash + predictive evaluation. Called from the V2 commit
    /// pipeline instead of running those evaluations synchronously inside `touchesBegan`.
    /// Coalesces: many key-downs in one runloop turn produce exactly one flush.
    private func scheduleSideEffectFlush() {
        guard !sideEffectFlushScheduled else { return }
        sideEffectFlushScheduled = true
        KeyboardResponsivenessTelemetry.shared.markSideEffectScheduled()
        DispatchQueue.main.async { [weak self] in
            self?.flushSideEffects()
        }
    }

    /// Run the deferred side-effects: read `documentContextBeforeInput` ONCE (always fresh,
    /// post-mutation), re-sync the context mirror from it, and feed it to slash / reminder /
    /// timer detection and predictive scheduling.
    private func flushSideEffects() {
        sideEffectFlushScheduled = false
        KeyboardResponsivenessTelemetry.shared.markSideEffectFlushed()
        // Refresh cached field traits here (coalesced, off the synchronous touch-down path) so the
        // next keystroke's commit reads them with zero XPC. Traits are field-constant, so being at
        // most one keystroke stale is harmless and field switches are picked up on the next change.
        refreshHostInputTraits()
        // Compare before replacing the mirror, so host-side transforms or caret changes
        // invalidate candidates even when the callback arrived inside our echo window.
        let context = resyncTypingContextFromHost()
        runSlashEvaluation(context: context)
        runReminderEvaluation(context: context)
        runTimerEvaluation(context: context)
        runPredictiveEvaluation(context: context)
    }

    /// NLP timer evaluation from an already-read context snapshot. Gated on the Timer integration —
    /// when it's off (or the snippet grid is showing), `/timer` is inert and no pill appears.
    private func runTimerEvaluation(context: String?) {
        guard timerIntegrationEnabled, qwertyState.surface == .typing else {
            timerSuggestionState.clear()
            return
        }
        timerSuggestionState.update(context: context)
    }

    /// NLP reminder evaluation from an already-read context snapshot. Cheap: `update` early-outs
    /// unless the text contains the `/remind` trigger, and the detector is allocated once.
    private func runReminderEvaluation(context: String?) {
        guard qwertyState.surface == .typing else {
            reminderSuggestionState.clear()
            return
        }
        reminderSuggestionState.update(context: context)
    }

    // MARK: - Reminder destination routing

    /// `.remindersApp` only when the integration is enabled AND it's the chosen destination;
    /// otherwise `.snipKey`. The selected destination always wins; a reminder is never created in
    /// both. (Both flags are session-cached, read once in `performDeferredSetup`.)
    private var effectiveReminderDestination: ReminderDestination {
        (remindersIntegrationEnabled && reminderDestination == .remindersApp) ? .remindersApp : .snipKey
    }

    /// Single funnel for creating a reminder. Only ever called from pill-accept (`/remind`) or the
    /// 🔔 button — never on the keystroke path — so EventKit work never touches typing performance.
    private func routeReminder(title: String, body: String, fireDate: Date) {
        switch effectiveReminderDestination {
        case .snipKey:
            // Existing behavior, untouched: a SnipKey local notification at the parsed time.
            LocalNotificationScheduler.schedule(
                ReminderRequest(fireDate: fireDate, title: title, message: body))

        case .remindersApp:
            // PRIMARY: write the EKReminder directly using the permission granted in the app.
            // Succeeds if the keyboard's process can see that grant (to be confirmed on-device).
            EventKitReminderService.create(title: body, dueDate: fireDate) { ok in
                guard !ok else { return }   // direct write succeeded — done, single artifact.
                // FALLBACK (reached only if iOS denied the keyboard's process / no calendar /
                // save error): schedule a SnipKey notification so the reminder is never lost.
                // The full "materialize in Reminders on next app open" hand-off (PendingReminderQueue)
                // is added only if the verification spike shows the direct write is blocked.
                LocalNotificationScheduler.schedule(
                    ReminderRequest(fireDate: fireDate, title: title, message: body))
            }
        }
    }

    // MARK: - Timer routing

    /// Single funnel for creating a timer. Only ever called from the `/timer` pill-accept — never on
    /// the keystroke path. Schedules a SnipKey local notification that fires when the countdown ends
    /// (the user stays in their current app).
    private func routeTimer(duration: TimeInterval, label: String) {
        LocalNotificationScheduler.schedule(
            ReminderRequest(fireDelay: duration, title: "Timer", message: "\(label) — time's up"))
    }

    /// Slash-command evaluation from an already-read context snapshot. Shared by the
    /// coalesced V2 flush and the synchronous V1 closure.
    private func runSlashEvaluation(context: String?) {
        // Skip evaluation when showing snippet grid (not in QWERTY mode).
        guard qwertyState.surface == .typing else { return }
        let result = slashCommandTracker.evaluate(context: context)
        if result.changed {
            slashCommandState.updateActivation(isActive: result.isActive, query: result.query)
        }
    }

    /// Predictive-text evaluation from an already-read context snapshot. Shared by the
    /// coalesced V2 flush and the synchronous V1 closure. The heavy UITextChecker work
    /// is dispatched off-main by `predictiveEngineAsync`.
    private func runPredictiveEvaluation(context: String?) {
        // Skip while hidden, when showing snippet grid, or when slash command is active.
        guard isKeyboardVisible, qwertyState.surface == .typing,
              cachedHostInputTraits.allowsSmartTransforms else {
            resetPredictivePipeline()
            return
        }
        guard !slashCommandState.isActive else {
            resetPredictivePipeline()
            return
        }
        // Yield the suggestion bar to the "Create reminder" pill when a /remind command is parsed.
        guard !reminderSuggestionState.isActive else {
            resetPredictivePipeline()
            return
        }
        guard !timerSuggestionState.isActive else {
            resetPredictivePipeline()
            return
        }
        // Swipe runner-ups own the bar while the swiped word (+ space) is still what's before
        // the caret; the next edit lets ordinary predictions take over.
        if predictiveTextState.candidates.first?.source == .swipe {
            if predictionContext == context.map({ String($0.suffix(64)) }) {
                return
            }
            resetPredictivePipeline()
        }
        // Parse the full host window before bounding the worker input: truncation must not
        // turn an embedded colon into a false start-of-document shortcode.
        let shortcode = context.flatMap(EmojiShortcodeQuery.parse)
        if let shortcode,
           !shortcode.canReplace(contextAfterInput: textDocumentProxy.documentContextAfterInput)
            || textDocumentProxy.selectedText?.isEmpty == false {
            resetPredictivePipeline()
            return
        }
        if predictiveTextState.partialWord != shortcode?.triggerText,
           shortcode != nil || predictiveTextState.isEmojiQueryActive {
            predictionContext = nil
        }
        predictiveTextState.prepareForEmojiQuery(shortcode?.triggerText)
        if shortcode != nil {
            updateTouchPrior(candidates: [], partialWord: "")
        }
        let boundedContext = context.map { String($0.suffix(64)) }
        predictiveEngineAsync.schedule(context: boundedContext) { [weak self] candidates, snapshot in
            guard let self else { return }
            guard self.qwertyState.surface == .typing,
                  let expected = snapshot.contextBeforeInput,
                  self.qwertyState.inputTracking.contextMirror.lastCharacters(64).elementsEqual(expected) else {
                self.resetPredictivePipeline()
                return
            }
            if shortcode != nil || snapshot.partialWord.hasPrefix(":"),
               shortcode?.triggerText != snapshot.partialWord {
                self.resetPredictivePipeline()
                return
            }
            self.predictionContext = expected
            self.predictiveTextState.updateCandidates(candidates, partialWord: snapshot.partialWord)
            self.updateTouchPrior(
                candidates: shortcode == nil ? candidates : [],
                partialWord: shortcode == nil ? snapshot.partialWord : ""
            )
        }
    }

    /// Toolbar runner-ups for a swiped word. Each candidate replaces the committed word AND
    /// its trailing space (`replacementLength`), and the existing suggestion-accept path
    /// re-inserts the chosen word + smart space.
    private func showSwipeAlternatives(committed: String, alternatives: [String]) {
        // Invalidate both debounced work and already-running results before taking over
        // the toolbar, including the no-runner-up case.
        resetPredictivePipeline()
        guard !alternatives.isEmpty else { return }
        let replaced = committed + " "
        let candidates = alternatives.map {
            PredictiveCandidate(
                text: $0,
                role: .completion,
                source: .swipe,
                confidence: 0.5,
                replacementLength: replaced.count
            )
        }
        predictionContext = String(qwertyState.inputTracking.contextMirror.lastCharacters(64))
        predictiveTextState.updateCandidates(candidates, partialWord: replaced)
    }

    private func insertQuickCommand(_ command: String) {
        guard isKeyboardVisible, qwertyState.surface == .typing,
              command == "/timer " || command == "/remind " else { return }
        let proxy = textDocumentProxy
        let before = proxy.documentContextBeforeInput
        let plan = CommandInsertionPlan.make(
            command: command, contextBeforeInput: before,
            contextAfterInput: proxy.documentContextAfterInput,
            hasSelection: proxy.selectedText?.isEmpty == false
        )
        nativeV2KeysView?.cancelActiveInteraction()
        qwertyState.inputTracking.contextMirror.reset(to: before)
        qwertyState.inputTracking.pendingSmartSpace = false
        qwertyState.inputTracking.resetAutoPeriodTracking()
        qwertyState.inputTracking.touchContext.recordNonCharacter()
        TouchOffsetModel.shared.discardPending()
        resetPredictivePipeline()
        slashCommandState.dismiss()
        reminderSuggestionState.clear()
        timerSuggestionState.clear()
        for _ in 0..<plan.deleteCount { deleteOwnBackward() }
        insertOwnText(plan.text)
        scheduleSideEffectFlush()
    }

    private func acceptPredictiveCandidate(_ candidate: PredictiveCandidate) {
        guard isKeyboardVisible, qwertyState.surface == .typing,
              predictiveTextState.candidates.contains(candidate),
              let expected = predictionContext,
              let currentContext = textDocumentProxy.documentContextBeforeInput,
              String(currentContext.suffix(64)) == expected,
              textDocumentProxy.selectedText?.isEmpty != false else {
            resetPredictivePipeline()
            scheduleTypingContextResync()
            return
        }
        if candidate.source == .emoji {
            guard let shortcode = EmojiShortcodeQuery.parse(currentContext),
                  shortcode.triggerText == predictiveTextState.partialWord,
                  shortcode.triggerText.count == candidate.replacementLength,
                  shortcode.canReplace(contextAfterInput: textDocumentProxy.documentContextAfterInput) else {
                resetPredictivePipeline()
                scheduleTypingContextResync()
                return
            }
            nativeV2KeysView?.cancelActiveInteraction()
            prepareEmojiEdit()
            qwertyState.inputTracking.contextMirror.reset(to: currentContext)
            for _ in 0..<candidate.replacementLength { deleteOwnBackward() }
            // A shortcode is replaced literally; do not add a space before punctuation
            // or disturb the user's existing whitespace after the caret.
            insertOwnText(candidate.text)
            inlineEmojiRecents.reload(allowSharedAccess: hasFullAccess)
            inlineEmojiRecents.record(candidate.text)
            qwertyState.handleShiftAfterCharacter()
            scheduleSideEffectFlush()
            return
        }
        resetPredictivePipeline()
        if candidate.role == .typed {
            insertOwnText(" ")
        } else {
            for _ in 0..<candidate.replacementLength { deleteOwnBackward() }
            insertOwnText(candidate.text + " ")
        }
        qwertyState.inputTracking.recordAction(.character)
        qwertyState.inputTracking.recordAction(.space)
        qwertyState.inputTracking.pendingSmartSpace = true
        qwertyState.handleShiftAfterCharacter()
        scheduleSideEffectFlush()
    }

    /// Clear every prediction surface, including the invisible next-character prior used by
    /// smart touch. Use whenever another toolbar mode owns the row or the context goes stale.
    private func resetPredictivePipeline() {
        predictionContext = nil
        predictiveTextState.dismiss()
        predictiveEngineAsync.reset()
        updateTouchPrior(candidates: [], partialWord: "")
    }

    /// Read the host field's input traits from `textDocumentProxy` / `UIInputViewController`
    /// (eight cross-process reads) plus the enabled input modes, and cache them. Called off
    /// the keystroke path only — `viewDidLoad`, `viewWillAppear`, external `textDidChange`,
    /// the coalesced `flushSideEffects`, and `currentInputModeDidChangeNotification`.
    private func refreshHostInputTraits() {
        let proxy = textDocumentProxy
        let needsSwitchKey = needsInputModeSwitchKey
        cachedHostInputTraits = HostInputTraits(
            keyboardType: proxy.keyboardType ?? .default,
            keyboardAppearance: proxy.keyboardAppearance ?? .default,
            returnKeyType: proxy.returnKeyType ?? .default,
            autocapitalizationType: proxy.autocapitalizationType ?? .sentences,
            autocorrectionType: proxy.autocorrectionType ?? .default,
            spellCheckingType: proxy.spellCheckingType ?? .default,
            smartQuotesEnabled: (proxy.smartQuotesType ?? .default) != .no,
            smartDashesEnabled: (proxy.smartDashesType ?? .default) != .no,
            autoCapitalizationEnabled: autoCapitalizationEnabled,
            needsInputModeSwitchKey: needsSwitchKey,
            localeCodes: needsSwitchKey ? Self.activeInputLocaleCodes() : []
        )
    }

    /// Uppercased language codes of the enabled input modes when more than one is enabled
    /// (matches Apple's "EN ES" space-bar subtitle in multilingual setups); empty otherwise.
    /// `UITextInputMode.activeInputModes` is a host query — refresh-time only.
    private static func activeInputLocaleCodes() -> [String] {
        let modes = UITextInputMode.activeInputModes
        guard modes.count > 1 else { return [] }
        return modes.compactMap { mode in
            guard let language = mode.primaryLanguage else { return nil }
            // Convert "en-US" → "EN", "es-MX" → "ES", etc.
            return String(language.prefix(while: { $0 != "-" })).uppercased()
        }
    }

    /// Derive a next-character prior from the in-progress word's top completions and push it
    /// onto the shared `ProbabilisticTouchContext`, so near-miss taps bias toward the letter
    /// that finishes the likely word ("after `thr` → enlarge `o`"). Runs in the predictive
    /// completion (already on the main actor), OFF every touch path, and adds no XPC read —
    /// it rides the existing coalesced flush. The same context object is read by
    /// `SmartTouchResolver` on the touch hot path via `weightsForRow`.
    private func updateTouchPrior(candidates: [PredictiveCandidate], partialWord: String) {
        let prior = Self.nextCharacterPrior(candidates: candidates, partialWord: partialWord)
        qwertyState.inputTracking.touchContext.updatePredictivePrior(prior, isEnglish: Self.isEnglishInputContext)
    }

    /// Build a `{nextChar: weight}` prior from the characters that would extend `partialWord`
    /// toward each top completion, weighted by suggestion rank. Returns nil below a 3-char
    /// prefix (the suggestion set is too noisy to bias touch targets that early).
    /// Tuning knobs (rank weights, prefix threshold) live here, at the point of use.
    static func nextCharacterPrior(candidates: [PredictiveCandidate], partialWord: String) -> [Character: Float]? {
        let prefixCount = partialWord.count
        guard prefixCount >= 3 else { return nil }
        let rankWeights: [Float] = [0.55, 0.30, 0.15]
        let lowerPartial = partialWord.lowercased()
        var prior: [Character: Float] = [:]
        var rankIndex = 0
        for candidate in candidates {
            if rankIndex >= rankWeights.count { break }
            guard candidate.role == .completion, candidate.confidence >= 0.70 else { continue }
            let lowerSuggestion = candidate.text.lowercased()
            // Only true completions of the partial word bias the next character.
            guard lowerSuggestion.count > prefixCount,
                  lowerSuggestion.hasPrefix(lowerPartial) else { continue }
            let nextChar = Array(lowerSuggestion)[prefixCount]
            guard nextChar.isLetter else { continue }
            // Distinct next-chars get descending rank weight; duplicates keep the higher rank.
            if prior[nextChar] == nil {
                prior[nextChar] = rankWeights[rankIndex]
                rankIndex += 1
            }
        }
        return prior.isEmpty ? nil : prior
    }

    /// Whether the active input language is English. The bigram tables are English-only, so
    /// for non-English input the blend uses the (language-correct) prediction prior alone.
    /// Mirrors the predictive engine's language source (`Locale.preferredLanguages`) so the
    /// English-ness check matches the language the suggestions were generated in.
    static var isEnglishInputContext: Bool {
        (Locale.preferredLanguages.first ?? "en").lowercased().hasPrefix("en")
    }

    // MARK: - V2 Keys Visibility

    /// Observation callbacks run after the surface mutation; only one surface receives touches.
    private func observeKeyboardSurface() {
        withObservationTracking {
            _ = qwertyState.surface
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.syncKeyboardSurface()
                self.observeKeyboardSurface()
            }
        }
    }

    private func syncKeyboardSurface() {
        nativeV2KeysView?.cancelActiveInteraction()
        emojiKeyboardView?.cancelInteraction()
        resetPredictivePipeline()
        qwertyState.inputTracking.pendingSmartSpace = false
        qwertyState.inputTracking.resetAutoPeriodTracking()
        qwertyState.inputTracking.touchContext.recordNonCharacter()
        slashCommandState.updateActivation(isActive: false, query: "")
        reminderSuggestionState.clear()
        timerSuggestionState.clear()
        nativeV2KeysView?.isHidden = qwertyState.surface != .typing
        if qwertyState.surface == .emoji {
            if emojiKeyboardView == nil {
                var actions = keyboardActionsStruct
                actions.insertText = { [weak self] text in
                    guard let self else { return }
                    self.prepareEmojiEdit()
                    self.insertOwnText(text)
                }
                actions.deleteBackward = { [weak self] in
                    guard let self else { return }
                    self.prepareEmojiEdit()
                    self.deleteOwnBackward()
                }
                let panel = EmojiKeyboardView(actions: actions, onReturnToTyping: { [weak self] in
                    self?.qwertyState.surface = .typing
                }, onSearchModeChanged: { [weak self] active in
                    guard let self else { return }
                    self.emojiSearchActive = active
                    self.updateKeyboardHeight()
                })
                panel.translatesAutoresizingMaskIntoConstraints = false
                view.insertSubview(panel, belowSubview: v2CalloutView)
                NSLayoutConstraint.activate([
                    panel.topAnchor.constraint(equalTo: view.topAnchor),
                    panel.bottomAnchor.constraint(equalTo: view.bottomAnchor),
                    panel.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                    panel.trailingAnchor.constraint(equalTo: view.trailingAnchor)
                ])
                emojiKeyboardView = panel
            }
            emojiKeyboardView?.isHidden = false
            emojiKeyboardView?.prepareForPresentation(isDark: qwertyState.appearanceMode == .dark)
        } else {
            emojiKeyboardView?.isHidden = true
            if qwertyState.surface == .typing { scheduleSideEffectFlush() }
        }
        updateKeyboardHeight()
    }

    private func prepareEmojiEdit() {
        qwertyState.inputTracking.pendingSmartSpace = false
        qwertyState.inputTracking.resetAutoPeriodTracking()
        qwertyState.inputTracking.touchContext.recordNonCharacter()
        TouchOffsetModel.shared.discardPending()
        resetPredictivePipeline()
    }

    // MARK: - QWERTY State Updates

    /// Push the cached host traits into the QWERTY keyboard state and recompute auto-cap.
    /// Reads only `cachedHostInputTraits`, the trait collection and the context mirror —
    /// never the proxy — so it is safe from any lifecycle hook. Callers that may be looking
    /// at a different field (`viewWillAppear`, external `textDidChange`, input-mode change)
    /// call `refreshHostInputTraits` first.
    private func updateQWERTYState() {
        let traits = cachedHostInputTraits

        // Keyboard appearance — respect the text field's explicit preference when set,
        // otherwise fall back to the system trait (so dark-mode users get dark V2 keys
        // even when the field is `.default`). Previously V2 always picked `.light`
        // whenever the proxy wasn't explicitly `.dark`.
        let newMode: KeyboardAppearanceMode
        switch traits.keyboardAppearance {
        case .dark:
            newMode = .dark
        case .light:
            newMode = .light
        default:
            newMode = self.traitCollection.userInterfaceStyle == .dark ? .dark : .light
        }
        if qwertyState.appearanceMode != newMode {
            qwertyState.appearanceMode = newMode
            if qwertyState.surface == .emoji {
                emojiKeyboardView?.prepareForPresentation(isDark: newMode == .dark)
            }
        }
        // Optional: `traitCollectionDidChange` can run before `viewDidLoad` creates the button.
        nextKeyboardButton?.setTitleColor(traits.keyboardAppearance == .dark ? .white : .black, for: [])
        
        // Globe key visibility — only mutate if changed
        if qwertyState.needsInputModeSwitchKey != traits.needsInputModeSwitchKey {
            qwertyState.needsInputModeSwitchKey = traits.needsInputModeSwitchKey
        }

        let newProfile = traits.layoutProfile
        if qwertyState.layoutProfile != newProfile {
            qwertyState.layoutProfile = newProfile
            qwertyState.currentPage = .letters
        }
        
        // Return key label — only mutate if changed
        updateReturnKeyLabel(traits.returnKeyType)

        updateAutoCapitalization()
    }

    /// Auto-capitalization from local state only (cached autocap trait + context mirror).
    /// Runs after every own insert/delete (via the host's synchronous `textDidChange`) and
    /// after every external change; `applyAutoCapitalization` only ever enables shift, so a
    /// `false` result leaves whatever the commit pipeline set.
    private func updateAutoCapitalization() {
        qwertyState.applyAutoCapitalization(shouldCapitalize: computeAutoCapitalization())
    }
    
    /// Open a URL from the keyboard extension by walking the responder chain.
    /// Tries the modern 3-argument open method first (via protocol cast),
    /// then falls back to the deprecated single-argument openURL: selector.
    private func openURL(_ url: URL) {
        var responder: UIResponder? = self
        while let r = responder {
            // Try modern open(_:options:completionHandler:) via file-scope protocol cast
            if let app = r as? KeyboardExtensionOpenURL {
                app.open(url, options: [:], completionHandler: nil)
                return
            }
            // Fallback: deprecated openURL: (still functional through iOS 26)
            let sel = NSSelectorFromString("openURL:")
            if r.responds(to: sel) {
                _ = r.perform(sel, with: url as NSURL)
                return
            }
            responder = r.next
        }
    }

    private func updateReturnKeyLabel(_ returnType: UIReturnKeyType) {
        let newLabel: String
        let newProminent: Bool
        
        switch returnType {
        case .go:
            newLabel = "Go"; newProminent = true
        case .join:
            newLabel = "Join"; newProminent = true
        case .next:
            newLabel = "Next"; newProminent = false
        case .search, .google, .yahoo:
            newLabel = "Search"; newProminent = true
        case .send:
            newLabel = "Send"; newProminent = true
        case .done:
            newLabel = "Done"; newProminent = true
        case .route:
            newLabel = "Route"; newProminent = true
        case .continue:
            newLabel = "Continue"; newProminent = true
        default:
            if let fallback = qwertyState.layoutProfile.fallbackReturnKey {
                newLabel = fallback.label
                newProminent = fallback.prominent
            } else {
                newLabel = "return"
                newProminent = false
            }
        }
        
        if qwertyState.returnKeyLabel != newLabel {
            qwertyState.returnKeyLabel = newLabel
        }
        if qwertyState.returnKeyIsProminent != newProminent {
            qwertyState.returnKeyIsProminent = newProminent
        }
    }
    
    /// Native auto-cap decision from local state: the session kill switch, the cached
    /// field trait and the context mirror. No host reads — safe inside the host's
    /// synchronous `textDidChange` re-entrancy on every keystroke.
    private func computeAutoCapitalization() -> Bool {
        // User-level kill switch (SnipKey Settings → Experimental → Auto-Capitalization).
        // When off, the keyboard never auto-caps regardless of what the text field requests.
        guard autoCapitalizationEnabled else {
            return false
        }
        return qwertyState.inputTracking.contextMirror.needsCapitalization(
            for: cachedHostInputTraits.autocapitalizationType)
    }
}


extension UIView {
    func addKeyboardSubview(_ subview: UIView){
        subview.translatesAutoresizingMaskIntoConstraints = false
        addSubview(subview)
        NSLayoutConstraint.activate([
            subview.leftAnchor.constraint(equalTo: leftAnchor),
            subview.rightAnchor.constraint(equalTo: rightAnchor),
            subview.topAnchor.constraint(equalTo: topAnchor),
            subview.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }
}
