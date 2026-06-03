//
//  KeyboardViewController.swift
//  SnipKeyboard
//
//  Created by Jonathan Taveras Vargas on 3/31/24.
//

import UIKit
import SwiftUI

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
    
    /// Character pop-up balloon — V1 single reusable UIKit view, positioned above pressed keys.
    /// Pure CALayer operations, zero SwiftUI state changes.
    private let popupView = KeyPopupView()

    /// V2 callout overlay — mounted on the root view so it can overlap the toolbar and
    /// draw above the top row of keys (which the V1 path achieves with `popupView`).
    /// Created always; only added to the view hierarchy when V2 is enabled.
    private let v2CalloutView = KeyboardCalloutView()

    /// V2 keys area, mounted as a DIRECT UIKit child of the input view (not inside the
    /// SwiftUI host). Keeping the keys in pure UIKit — like the native/Grammarly keyboard —
    /// means keys-area touches bypass SwiftUI's event-aware hit-testing entirely, so there
    /// are no dead zones between keys. Only created when V2 is enabled.
    private var nativeV2KeysView: NativeKeyboardV2View?
    
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

    // MARK: - Hot-path coalescing (V2)

    /// True only during the host's synchronous `textDidChange` re-entrancy triggered by our
    /// own committed-character insert. Lets `updateQWERTYState` skip the redundant
    /// auto-capitalization context read (a just-typed character can't start a sentence/word,
    /// so `.words`/`.sentences` would compute false anyway). `.allCharacters` is still honored.
    private var ownCharacterInsertInFlight = false

    /// Coalescer guard: ensures at most one deferred side-effect flush is queued per runloop.
    /// V2 commits schedule slash + predictive evaluation here instead of running them
    /// synchronously inside `touchesBegan`, so a fast burst collapses to one context read
    /// (and one slash/predictive pass) per frame.
    private var sideEffectFlushScheduled = false
    
    /// Wraps textDocumentProxy operations as closures for the SwiftUI QWERTY keyboard
    private lazy var keyboardActionsStruct: KeyboardActions = {
        KeyboardActions(
            insertText: { [weak self] text in
                self?.textDocumentProxy.insertText(text)
            },
            insertCharacter: { [weak self] text in
                guard let self = self else { return }
                // Mark the host's synchronous textDidChange re-entrancy as our own insert
                // so updateQWERTYState can skip the redundant auto-cap context read.
                self.ownCharacterInsertInFlight = true
                self.textDocumentProxy.insertText(text)
                self.ownCharacterInsertInFlight = false
            },
            deleteBackward: { [weak self] in
                self?.textDocumentProxy.deleteBackward()
            },
            advanceToNextInputMode: { [weak self] in
                self?.advanceToNextInputMode()
            },
            documentContextBeforeInput: { [weak self] in
                self?.textDocumentProxy.documentContextBeforeInput
            },
            screenWidth: keyboardScreenWidth(),
            showPopup: { [weak self] character, keyFrame, isDark in
                self?.popupView.show(character: character, keyFrame: keyFrame, isDark: isDark)
            },
            hidePopup: { [weak self] in
                self?.popupView.hide()
            },
            openApp: { [weak self] in
                if let url = URL(string: "snipkey://open") {
                    self?.openURL(url)
                }
            },
            evaluateSlashCommand: { [weak self] in
                // V1 path: read context and evaluate synchronously.
                guard let self = self else { return }
                self.runSlashEvaluation(context: self.textDocumentProxy.documentContextBeforeInput)
            },
            evaluatePredictiveText: { [weak self] in
                // V1 path: read context and schedule synchronously.
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
                self.textDocumentProxy.adjustTextPosition(byCharacterOffset: delta)
            },
            inputTraits: { [weak self] in
                guard let proxy = self?.textDocumentProxy else { return .defaults }
                return HostInputTraits(
                    keyboardType: proxy.keyboardType ?? .default,
                    autocapitalizationType: proxy.autocapitalizationType ?? .sentences,
                    smartQuotesEnabled: (proxy.smartQuotesType ?? .default) != .no,
                    smartDashesEnabled: (proxy.smartDashesType ?? .default) != .no
                )
            },
            activeInputLocaleCodes: { [weak self] in
                guard let self else { return [] }
                // Show locale codes when the user has multiple keyboards enabled (matches
                // Apple's "EN ES" subtitle on the space bar in multilingual setups).
                guard self.needsInputModeSwitchKey else { return [] }
                let modes = UITextInputMode.activeInputModes
                guard modes.count > 1 else { return [] }
                return modes.compactMap { mode in
                    guard let language = mode.primaryLanguage else { return nil }
                    // Convert "en-US" → "EN", "es-MX" → "ES", etc.
                    return String(language.prefix(while: { $0 != "-" })).uppercased()
                }
            },
            v2CalloutView: v2CalloutView
        )
    }()
    
    override func updateViewConstraints() {
        super.updateViewConstraints()
        
        // Add custom view sizing constraints here
    }
    
    // Helper method to check if full access is enabled
    func hasFullAccess() -> Bool {
        return self.hasFullAccess
    }
    
    func sendImageData(snippet: SnippetItem) {
        if self.hasFullAccess {
            guard
                let newImage = UIImage(data: (snippet.file?.fileData)!)
            else { return }
            
            var imageData: Data?
            
            if snippet.file?.fileFormatType == "image/png"{
                imageData = newImage.pngData()
            }
            
            if snippet.file?.fileFormatType == "image/jpeg"{
                imageData = newImage.jpegData(compressionQuality: 0.5)
            }
            
            
            let clipboard = UIPasteboard.general
            UIPasteboard.general.string = " "
            clipboard.setData(imageData!, forPasteboardType: UTType.png.identifier)
        }
    }
    
    func sendPDFData(snippet: SnippetItem) {
        if self.hasFullAccess {
            guard let pdfData = snippet.file?.fileData else { return }
            
            let clipboard = UIPasteboard.general
            clipboard.string = " "
            clipboard.colors = [UIColor(Color(.red))]
            clipboard.setData(pdfData, forPasteboardType: UTType.pdf.identifier)
        }
    }
    
    func getSelectedText() -> String {
        if self.textDocumentProxy.hasText {
            let selectedText = self.textDocumentProxy.selectedText ?? ""
            print("has text selected \(selectedText)")
            return selectedText
        }
        
        return ""
    }
    
    
    
    override func viewDidLoad() {
        super.viewDidLoad()

        // Kick off SwiftData container construction immediately on a background task,
        // so it's typically ready by the time SwiftUI mounts and `.task` awaits it.
        // Without this warmup, first-keyboard-open paid ~50–200ms of synchronous
        // SQLite + CloudKit setup on the main thread.
        Task { await ModelContainerProvider.shared.warmup() }

        // Perform custom UI setup here
        self.nextKeyboardButton = UIButton(type: .system)
        
        self.nextKeyboardButton.setTitle(NSLocalizedString("Next Keyboard", comment: "Title for 'Next Keyboard' button"), for: [])
        self.nextKeyboardButton.sizeToFit()
        self.nextKeyboardButton.translatesAutoresizingMaskIntoConstraints = false
        
        self.nextKeyboardButton.addTarget(self, action: #selector(handleInputModeList(from:with:)), for: .allTouchEvents)
        
        self.view.addSubview(self.nextKeyboardButton)
        
        self.nextKeyboardButton.leftAnchor.constraint(equalTo: self.view.leftAnchor).isActive = true
        self.nextKeyboardButton.bottomAnchor.constraint(equalTo: self.view.bottomAnchor).isActive = true
        
        // Cache supplementary lexicon for predictive text (contacts, shortcuts)
        requestSupplementaryLexicon { [weak self] lexicon in
            self?.predictiveEngineAsync.lexicon = lexicon
        }
        
        // Host SwiftUI keyboard with QWERTY state and actions injected
        let contentView = UIHostingController(
            rootView: KeyboardViewExt(
                qwertyState: qwertyState,
                keyboardActions: keyboardActionsStruct,
                slashCommandState: slashCommandState,
                predictiveTextState: predictiveTextState
            )
        )
        
        contentView.view.backgroundColor = .clear

        view.addKeyboardSubview(contentView.view)

        // V2 keys area as a direct UIKit child of the input view, ABOVE the SwiftUI host but
        // BELOW the popup/callout overlays. The SwiftUI side (`NativeKeyboardV2View_SwiftUI`)
        // now renders only the toolbar; this view draws and handles touches for all the keys.
        // This removes SwiftUI's hit-testing from the keys touch path — the native model —
        // so taps in the gaps between keys always reach the gesture coordinator.
        if AppGroupSettings.bool(forKey: AppGroupSettings.Key.useNativeKeyboardV2, default: true) {
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
            keysView.isHidden = qwertyState.showingSnippets
            observeSnippetsForKeysVisibility()
        }

        // Add popup view on top of the SwiftUI content (renders above all keys)
        popupView.translatesAutoresizingMaskIntoConstraints = true
        view.addSubview(popupView)

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
        
        // insert text to textInput
        NotificationCenter.default.addObserver(forName: NSNotification.Name(rawValue: "addKey"), object: nil, queue: nil){ [weak self] notification in
            guard let self = self else { return }

            if let snippet = notification.object as? SnippetItem {
                switch snippet.type {
                case .image:
                    self.sendImageData(snippet: snippet)
                case .file:
                    self.sendPDFData(snippet: snippet)
                default:
                    self.textDocumentProxy.insertText(snippet.content!)
                }

            }

            if let text = notification.object as? String {
                self.textDocumentProxy.insertText(text)
            }
        }

        // Listen to swicthKeyboard
        NotificationCenter.default.addObserver(forName: NSNotification.Name(rawValue: "switchKey"), object: nil, queue: nil){ [weak self] _ in
            //            Switch Keyboard
            self?.advanceToNextInputMode()
        }
        
        
        // Delete text
        //        NotificationCenter.default.addObserver(forName: NSNotification.Name(rawValue: "deleteKey"), object: nil, queue: nil){ _ in
        //            self.textDocumentProxy.deleteBackward()
        //        }
        
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name(rawValue: "deleteKey"),
            object: nil,
            queue: nil
        ) { [weak self] notification in
            if let isLongPress = notification.object as? Bool {
                self?.handleDelete(isLongPress: isLongPress)
            }
        }
        
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name(rawValue: "spaceKey"),
            object: nil,
            queue: nil
        ) { [weak self] _ in
            self?.textDocumentProxy.insertText(" ")
        }

        // Tell the system we want to defer left/right edge system gestures (see the
        // `preferredScreenEdgesDeferringSystemGestures` override). Must be called after the
        // view hierarchy is set up; re-applied in `viewWillAppear`.
        setNeedsUpdateOfScreenEdgesDeferringSystemGestures()
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
                self.textDocumentProxy.deleteBackward()
            }
        } else {
            // Single tap
            isLongPressing = false
            deletionCount = 0
            self.textDocumentProxy.deleteBackward()
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
        setNeedsUpdateOfScreenEdgesDeferringSystemGestures()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        // Persist shadow-mode telemetry off the hot path (no-op unless shadow logging is on).
        TypingTelemetry.shared.flush()
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
        self.nextKeyboardButton.isHidden = !self.needsInputModeSwitchKey
        // Update height constraint on layout changes (rotation, different device)
        let newWidth = keyboardScreenWidth()
        heightConstraint?.constant = KeyboardDimensions.totalHeight(forScreenWidth: newWidth)
        // Only update QWERTY state when screen width actually changed (rotation)
        // This avoids doubling observable mutations since textDidChange also calls updateQWERTYState
        if newWidth != lastKnownWidth {
            lastKnownWidth = newWidth
            updateQWERTYState()
        }
        super.viewWillLayoutSubviews()
    }
    
    override func textWillChange(_ textInput: UITextInput?) {
        // The app is about to change the document's contents. Perform any preparation here.
        
    }
    
    override func textDidChange(_ textInput: UITextInput?) {
        // The app has just changed the document's contents, the document context has been updated.

        let textColor: UIColor
        let proxy = self.textDocumentProxy
        if proxy.keyboardAppearance == UIKeyboardAppearance.dark {
            textColor = UIColor.white
        } else {
            textColor = UIColor.black
        }
        self.nextKeyboardButton.setTitleColor(textColor, for: [])
        
        // Update QWERTY keyboard state from text document proxy
        updateQWERTYState()
        
        // Only post selection notifications when snippet view is active.
        // These are consumed by KeyboardView's observers and serve no purpose
        // during QWERTY typing — skipping them avoids N observer calls per keystroke.
        if qwertyState.showingSnippets {
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
        DispatchQueue.main.async { [weak self] in
            self?.flushSideEffects()
        }
    }

    /// Run the deferred side-effects: read `documentContextBeforeInput` ONCE (always fresh,
    /// post-mutation) and feed it to both slash detection and predictive scheduling.
    private func flushSideEffects() {
        sideEffectFlushScheduled = false
        let context = textDocumentProxy.documentContextBeforeInput
        runSlashEvaluation(context: context)
        runPredictiveEvaluation(context: context)
    }

    /// Slash-command evaluation from an already-read context snapshot. Shared by the
    /// coalesced V2 flush and the synchronous V1 closure.
    private func runSlashEvaluation(context: String?) {
        // Skip evaluation when showing snippet grid (not in QWERTY mode).
        guard !qwertyState.showingSnippets else { return }
        let result = slashCommandTracker.evaluate(context: context)
        if result.changed {
            slashCommandState.updateActivation(isActive: result.isActive, query: result.query)
        }
    }

    /// Predictive-text evaluation from an already-read context snapshot. Shared by the
    /// coalesced V2 flush and the synchronous V1 closure. The heavy UITextChecker work
    /// is dispatched off-main by `predictiveEngineAsync`.
    private func runPredictiveEvaluation(context: String?) {
        // Skip when showing snippet grid or when slash command is active.
        guard !qwertyState.showingSnippets else { return }
        guard !slashCommandState.isActive else {
            // Clear suggestions when slash is active.
            predictiveTextState.dismiss()
            return
        }
        predictiveEngineAsync.schedule(context: context) { [weak self] suggestions, partialWord in
            guard let self else { return }
            self.predictiveTextState.updateSuggestions(suggestions: suggestions, partialWord: partialWord)
            self.updateTouchPrior(suggestions: suggestions, partialWord: partialWord)
        }
    }

    /// Derive a next-character prior from the in-progress word's top completions and push it
    /// onto the shared `ProbabilisticTouchContext`, so near-miss taps bias toward the letter
    /// that finishes the likely word ("after `thr` → enlarge `o`"). Runs in the predictive
    /// completion (already on the main actor), OFF every touch path, and adds no XPC read —
    /// it rides the existing coalesced flush. The same context object is read by
    /// `SmartTouchResolver` on the touch hot path via `weightsForRow`.
    private func updateTouchPrior(suggestions: [String], partialWord: String) {
        let prior = Self.nextCharacterPrior(suggestions: suggestions, partialWord: partialWord)
        qwertyState.inputTracking.touchContext.updatePredictivePrior(prior, isEnglish: Self.isEnglishInputContext)
    }

    /// Build a `{nextChar: weight}` prior from the characters that would extend `partialWord`
    /// toward each top completion, weighted by suggestion rank. Returns nil below a 2-char
    /// prefix (the suggestion set is too noisy to bias touch targets that early).
    /// Tuning knobs (rank weights, prefix threshold) live here, at the point of use.
    static func nextCharacterPrior(suggestions: [String], partialWord: String) -> [Character: Float]? {
        let prefixCount = partialWord.count
        guard prefixCount >= 2 else { return nil }
        let rankWeights: [Float] = [0.7, 0.2, 0.1]
        let lowerPartial = partialWord.lowercased()
        var prior: [Character: Float] = [:]
        var rankIndex = 0
        for suggestion in suggestions {
            if rankIndex >= rankWeights.count { break }
            let lowerSuggestion = suggestion.lowercased()
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

    /// Keep the directly-mounted V2 keys view in sync with `showingSnippets`: hide it while
    /// the snippet grid is showing (the SwiftUI host draws the grid full-screen), show it when
    /// the keyboard is up. `withObservationTracking` fires once per registration, so we
    /// re-register inside the callback to keep listening — same pattern as `NativeKeyboardV2View`.
    private func observeSnippetsForKeysVisibility() {
        withObservationTracking {
            _ = qwertyState.showingSnippets
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.nativeV2KeysView?.isHidden = self.qwertyState.showingSnippets
                self.observeSnippetsForKeysVisibility()
            }
        }
    }

    // MARK: - QWERTY State Updates

    /// Push text input context from textDocumentProxy into the QWERTY keyboard state.
    /// Called on textDidChange and viewWillLayoutSubviews.
    private func updateQWERTYState() {
        let proxy = self.textDocumentProxy

        // Keyboard appearance — respect the text field's explicit preference when set,
        // otherwise fall back to the system trait (so dark-mode users get dark V2 keys
        // even when the field is `.default`). Previously V2 always picked `.light`
        // whenever the proxy wasn't explicitly `.dark`.
        let newMode: KeyboardAppearanceMode
        switch proxy.keyboardAppearance {
        case .dark:
            newMode = .dark
        case .light:
            newMode = .light
        default:
            newMode = self.traitCollection.userInterfaceStyle == .dark ? .dark : .light
        }
        if qwertyState.appearanceMode != newMode {
            qwertyState.appearanceMode = newMode
        }
        
        // Globe key visibility — only mutate if changed
        let newNeedsSwitch = self.needsInputModeSwitchKey
        if qwertyState.needsInputModeSwitchKey != newNeedsSwitch {
            qwertyState.needsInputModeSwitchKey = newNeedsSwitch
        }
        
        // Return key label — only mutate if changed
        updateReturnKeyLabel()

        // Auto-capitalization
        if ownCharacterInsertInFlight {
            // This is the host's synchronous textDidChange re-entrancy from our own
            // committed character. A just-typed character can never make the context end
            // in a sentence/word boundary, so `.words`/`.sentences` would compute `false`
            // anyway — skip them (and their cross-process context read) entirely, leaving
            // shift exactly as the commit pipeline set it. Only `.allCharacters` (which
            // reads no context) still needs re-asserting so all-caps fields stay capitalized.
            let autocapType = textDocumentProxy.autocapitalizationType ?? .none
            let autoCapEnabled = AppGroupSettings.bool(
                forKey: AppGroupSettings.Key.autoCapitalizationEnabled, default: true
            )
            if autoCapEnabled && autocapType == .allCharacters {
                qwertyState.applyAutoCapitalization(shouldCapitalize: true)
            }
        } else {
            // Host-initiated change (or space/return/backspace commit) — full recompute.
            let shouldCap = computeAutoCapitalization()
            qwertyState.applyAutoCapitalization(shouldCapitalize: shouldCap)
        }
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

    private func updateReturnKeyLabel() {
        let returnType = textDocumentProxy.returnKeyType ?? .default
        
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
            newLabel = "return"; newProminent = false
        }
        
        if qwertyState.returnKeyLabel != newLabel {
            qwertyState.returnKeyLabel = newLabel
        }
        if qwertyState.returnKeyIsProminent != newProminent {
            qwertyState.returnKeyIsProminent = newProminent
        }
    }
    
    private func computeAutoCapitalization() -> Bool {
        // User-level kill switch (SnipKey Settings → Experimental → Auto-Capitalization).
        // When off, the keyboard never auto-caps regardless of what the text field requests.
        guard AppGroupSettings.bool(forKey: AppGroupSettings.Key.autoCapitalizationEnabled, default: true) else {
            return false
        }

        let proxy = textDocumentProxy
        let autocapType = proxy.autocapitalizationType ?? .none

        switch autocapType {
        case .none:
            return false
        case .allCharacters:
            return true
        case .words:
            let before = proxy.documentContextBeforeInput ?? ""
            return before.isEmpty || before.last?.isWhitespace == true
        case .sentences:
            let before = proxy.documentContextBeforeInput ?? ""
            return before.isEmpty
                || before.hasSuffix(". ") || before.hasSuffix("? ") || before.hasSuffix("! ")
                || before.hasSuffix("\n")
        @unknown default:
            return false
        }
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
