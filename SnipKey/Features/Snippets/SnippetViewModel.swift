//
//  SnippetViewModel.swift
//  SnipKey
//
//  Created by Jonathan Taveras Vargas on 3/27/24.
//

import SwiftData
import SwiftUI

extension SnippetView {
    @Observable
    class ViewModel {
        var modelContext: ModelContext
        var snippets = [SnippetItem]()
        
        init(modelContext: ModelContext) {
            self.modelContext = modelContext
            fetchData()
        }
        
        func deleteItems(offsets: IndexSet) {
            withAnimation {
                for index in offsets {
                    self.modelContext.delete(self.snippets[index])
                }
                
            }
            fetchData()
        }
        
        func addItem(_ title: String, content: String, tag: Tags?, type: SnipType?) {
            print("ADD FUNC CALLED!")
            withAnimation {
                let newItem = SnippetItem(title: title, content: content, tag: tag, type: type ?? .txt)
                self.modelContext.insert(newItem)
               
            }
            fetchData()
        }
        
        func fetchData() {
            do {
                let descriptor = FetchDescriptor<SnippetItem>()
                snippets = try modelContext.fetch(descriptor)
            } catch {
                print("Fetch failed")
            }
        }
    }
}
