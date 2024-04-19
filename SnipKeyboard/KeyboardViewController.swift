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
    let container = SnipKeyDataManager().makeSharedContainer()
    private let keyboardView = KeyboardView()
    
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
            clipboard.setValue(imageData!, forPasteboardType: UTType.png.identifier)
        }
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
        
        view.addKeyboardSubview(UIHostingController(rootView: keyboardView.modelContext(container.mainContext)).view)
        
        // insert text to textInput
        NotificationCenter.default.addObserver(forName: NSNotification.Name(rawValue: "addKey"), object: nil, queue: nil){ notification in
            
            if let snippet = notification.object as? SnippetItem {
                switch snippet.type {
                case .image:
                    self.sendImageData(snippet: snippet)
                default:
                    self.textDocumentProxy.insertText(snippet.content)
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
        NotificationCenter.default.addObserver(forName: NSNotification.Name(rawValue: "deleteKey"), object: nil, queue: nil){ _ in
            self.textDocumentProxy.deleteBackward()
            
//            // Move the text insertion position forward 1 character
//            self.textDocumentProxy.adjustTextPosition(byCharacterOffset: -40)


            // Delete the previous character
//            self.textDocumentProxy.deleteBackward()

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
