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

class KeyboardViewController: UIInputViewController {

    @IBOutlet var nextKeyboardButton: UIButton!
    
    var isLongPressing = false
    var deletionCount = 0
//    let container = SnipKeyDataManager().makeSharedContainer()
//    private let keyboardView = KeyboardViewExt()
    
    override func updateViewConstraints() {
        super.updateViewConstraints()
        
        // Add custom view sizing constraints here
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
        
        let contentView = UIHostingController(rootView: KeyboardViewExt())
        
        view.addKeyboardSubview(contentView.view)
        
        
//        Alternative way to inject swiftdata context to view
//        view.addKeyboardSubview(UIHostingController(rootView: keyboardView.modelContext(container.mainContext)).view)
        
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
