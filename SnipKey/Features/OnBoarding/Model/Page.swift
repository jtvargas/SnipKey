//
//  Page.swift
//  SnipKey
//
//  Created by Jonathan Taveras Vargas on 9/25/24.
//


import Foundation

enum Page: String, CaseIterable {
    case page1 = "sparkles"
    case page2 = "text.insert"
    case page3 = "text.badge.plus"
    case page4 =  "lock.shield.fill"
    case page5 = "gearshape.fill"
    
    var title: String {
        switch self {
        case .page1: "Welcome to SnipKey"
        case .page2: "Save Time, Type Quicker"
        case .page3: "Use Commands Anywhere"
        case .page4: "Your Data is Safe"
        case .page5: "✋Set Up Your Keyboard"
        }
    }
    
    var media: [MediaItem] {
        switch self {
        case .page1: [
            MediaItem(
                name: "shortcuts-bubble",
                type: .image
            ),MediaItem(
                name: "snipkey-icon-new",
                type: .image
            )
        ]
            
        case .page2: [
            MediaItem(
                name: "keyboard-switch",
                type: .image
            )
            ]
        case .page3: [
            MediaItem(
                name: "quick-creation",
                type: .image
            ),
        ] case .page4: [
            MediaItem(
                name: "data-secure",
                type: .image
            ),
        ]
        case .page5: [
            MediaItem(
                name: "settings-dark-keyboard",
                type: .image
            ),MediaItem(
                name: "settings-dark-keyboard2",
                type: .image
            ),
        ]
        }
    }
    
    var subTitle: String {
        switch self {
        case .page1: "Access text and image snippets instantly with the keyboard extension.\n\nSave time using quick shortcuts."
        case .page2:  "Create snippets for frequently used text and URLs.\n\nAccess and paste them anywhere with the keyboard extension."
        case .page3: "Type commands like “/remind tomorrow at 9am call mom” to quickly create reminders with natural language.\n\nKeep reminders inside SnipKey or connect Apple Reminders from Settings."
        case .page4: "All your snippets are encrypted and synced across devices with iCloud."
        case .page5: "1. Open App Settings > Keyboards.\n2. Turn on 'Shortcuts'.\n3. Enable 'Full Access' for media features like images and PDFs."
        }
    }
    
    var index: CGFloat {
        switch self {
        case .page1: 0
        case .page2: 1
        case .page3: 2
        case .page4: 3
        case .page5: 4
        }
    }
    
    var nextPage: Page {
        let index = Int(self.index) + 1
        
        if index < 5 {
            return Page.allCases[index]
        }
        
        return .page1
    }
    
    var previousPage: Page {
        let index = Int(self.index) - 1
        
        if index >= 0 {
            return Page.allCases[index]
        }
        
        return .page5
    }
    
}

struct MediaItem: Identifiable {
    let id = UUID()
    let name: String
    let type: MediaType
    
    enum MediaType {
        case image
        case video(String)  // String represents the file extension (e.g., "mov")
    }
}
