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
    
    /// Character pop-up balloon — single reusable UIKit view, positioned above pressed keys.
    /// Pure CALayer operations, zero SwiftUI state changes.
    private let popupView = KeyPopupView()
    
    // MARK: - Slash Command
    
    /// Slash command detection — plain class, zero SwiftUI re-renders per keystroke.
    /// Only promotes to @Observable state when the active/query status actually changes.
    private let slashCommandTracker = SlashCommandTracker()
    
    /// Observable slash command state — shared with SwiftUI toolbar for suggestions display.
    let slashCommandState = SlashCommandState()
    
    // MARK: - Predictive Text
    
    /// Predictive text detection — plain class, zero SwiftUI re-renders per keystroke.
    /// Only promotes to @Observable state when suggestions actually change.
    private let predictiveTextTracker = PredictiveTextTracker()
    
    /// Observable predictive text state — shared with SwiftUI toolbar for suggestions display.
    let predictiveTextState = PredictiveTextState()
    
    /// Wraps textDocumentProxy operations as closures for the SwiftUI QWERTY keyboard
    private lazy var keyboardActionsStruct: KeyboardActions = {
        KeyboardActions(
            insertText: { [weak self] text in
                self?.textDocumentProxy.insertText(text)
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
            screenWidth: UIScreen.main.bounds.width,
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
                guard let self = self else { return }
                // Skip evaluation when showing snippet grid (not in QWERTY mode)
                guard !self.qwertyState.showingSnippets else { return }
                let context = self.textDocumentProxy.documentContextBeforeInput
                let result = self.slashCommandTracker.evaluate(context: context)
                if result.changed {
                    self.slashCommandState.updateActivation(
                        isActive: result.isActive,
                        query: result.query
                    )
                }
            },
            evaluatePredictiveText: { [weak self] in
                guard let self = self else { return }
                // Skip when showing snippet grid or when slash command is active
                guard !self.qwertyState.showingSnippets else { return }
                guard !self.slashCommandState.isActive else {
                    // Clear suggestions when slash is active
                    self.predictiveTextState.dismiss()
                    return
                }
                let context = self.textDocumentProxy.documentContextBeforeInput
                let result = self.predictiveTextTracker.evaluate(context: context)
                if result.changed {
                    self.predictiveTextState.updateSuggestions(
                        suggestions: result.suggestions,
                        partialWord: result.partialWord
                    )
                }
            }
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
            self?.predictiveTextTracker.lexicon = lexicon
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
        
        // Add popup view on top of the SwiftUI content (renders above all keys)
        popupView.translatesAutoresizingMaskIntoConstraints = true
        view.addSubview(popupView)
        
        // Set explicit height constraint so the system knows how tall the keyboard should be.
        // Without this, GeometryReader (now removed) would fail to communicate height upward.
        let desiredHeight = KeyboardDimensions.totalHeight(forScreenWidth: UIScreen.main.bounds.width)
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
        NotificationCenter.default.addObserver(forName: NSNotification.Name(rawValue: "addKey"), object: nil, queue: nil){ notification in
            
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
        NotificationCenter.default.addObserver(forName: NSNotification.Name(rawValue: "switchKey"), object: nil, queue: nil){ _ in
            //            Switch Keyboard
            self.advanceToNextInputMode()
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
        ) { _ in
            self.textDocumentProxy.insertText(" ")
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
                self.textDocumentProxy.deleteBackward()
            }
        } else {
            // Single tap
            isLongPressing = false
            deletionCount = 0
            self.textDocumentProxy.deleteBackward()
        }
    }
    
    override func viewWillLayoutSubviews() {
        self.nextKeyboardButton.isHidden = !self.needsInputModeSwitchKey
        // Update height constraint on layout changes (rotation, different device)
        let newWidth = UIScreen.main.bounds.width
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
        
        var textColor: UIColor
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
    
    // MARK: - QWERTY State Updates
    
    /// Push text input context from textDocumentProxy into the QWERTY keyboard state.
    /// Called on textDidChange and viewWillLayoutSubviews.
    private func updateQWERTYState() {
        let proxy = self.textDocumentProxy
        
        // Keyboard appearance (light/dark) — only mutate if changed
        let newMode: KeyboardAppearanceMode = proxy.keyboardAppearance == .dark ? .dark : .light
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
        let shouldCap = computeAutoCapitalization()
        qwertyState.applyAutoCapitalization(shouldCapitalize: shouldCap)
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
