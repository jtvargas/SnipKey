//
//  SnippetViewModel.swift
//  SnipKey
//
//  Created by Jonathan Taveras Vargas on 3/27/24.
//

import SwiftData
import SwiftUI

@Observable
class ViewModel {
    var modelContext: ModelContext? = nil
    
    func deleteItems(offsets: IndexSet, snippets:  [SnippetItem]) {
        for index in offsets {
            self.modelContext?.delete(snippets[index])
        }
    }
    
    func addItem(_ title: String, content: String, tag: Tags?, type: SnipType?) {
        if (title.isEmpty && content.isEmpty){
            print("empty, no add")
        } else {
            print("ADD FUNC CALLED!")
            let newItem = SnippetItem(title: title, content: content, tag: tag, type: type ?? .txt)
            self.modelContext?.insert(newItem)
            
        }
    }
}

