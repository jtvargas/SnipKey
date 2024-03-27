//
//  ContentView.swift
//  SnipKey
//
//  Created by Jonathan Taveras Vargas on 3/25/24.
//

import SwiftUI
import SwiftData

struct SnippetView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var items: [SnippetItem]
    
    var body: some View {
        NavigationSplitView {
            SnippetList(items: items, onDeleteHandler: deleteItems(offsets:))
                .navigationTitle("SnipKey")
                .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    EditButton()
                }
                
                ToolbarItem {
                    Button(action: addItem) {
                        Label("Add Item", systemImage: "plus")
                    }
                }
            }
        } detail: {
            Text("Select an item")
        }
    }
    
    private func addItem() {
        withAnimation {
            let newItem = SnippetItem(timestamp: Date())
            modelContext.insert(newItem)
        }
    }
    
    private func deleteItems(offsets: IndexSet) {
        withAnimation {
            for index in offsets {
                modelContext.delete(items[index])
            }
        }
    }
}

#Preview {
    SnippetView()
        .modelContainer(for: SnippetItem.self, inMemory: true)
}
