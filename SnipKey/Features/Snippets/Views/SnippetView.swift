//
//  ContentView.swift
//  SnipKey
//
//  Created by Jonathan Taveras Vargas on 3/25/24.
//

import SwiftUI
import SwiftData

struct SnippetView: View {
    @State var showSnippedDetailSheet = false
    @State private var viewModel: ViewModel
    @State private var showModal = false
    @State private var selectedSnippet: SnippetItem?
    @State var isPresented: Bool = false

    
    func toggleFormModal(){
        self.isPresented.toggle()
    }
    
    func handleOnSavePress(_ title: String, _ content: String, _ tag: Tags, _ type: SnipType){
        print("Title: \(title), \(content)")
        viewModel.addItem(title, content: content, tag: tag, type: type)
        toggleFormModal()
    }
    

    var body: some View {
        NavigationSplitView{
            SnippetList(items: viewModel.snippets, onDeleteHandler: viewModel.deleteItems(offsets:))
                .navigationTitle("SnipKey")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        EditButton()
                    }
                    
                    ToolbarItem {
                        Button(action: toggleFormModal) {
                            Label("Add Item", systemImage: "plus")
                        }.sheet(isPresented: $isPresented) { // Passing the state to the sheet API
                            SnippetForm(onClosePress: toggleFormModal, onSavePress: handleOnSavePress)
                                .interactiveDismissDisabled()
                        }
                    }
                }
        }detail: {
            Text("DETAIL")
        }
    }
    
    
    init(modelContext: ModelContext){
        let viewModel = ViewModel(modelContext: modelContext)
        _viewModel = State(initialValue: viewModel)
    }
}


#Preview {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            SnippetItem.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        
        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()
    
    return SnippetView(modelContext: sharedModelContainer.mainContext)
        .modelContainer(sharedModelContainer)
}
