//
//  TagsView.swift
//  SnipKey
//
//  Created by Jonathan Taveras Vargas on 5/10/24.
//

import SwiftUI
import SwiftData

struct TagsView: View {
    @Environment(\.modelContext) var modelContext
    @Query() private var tags: [SnipTag]
    
    @State var isEditMode: EditMode = .inactive
  
    @State private var navigationTitletext = "Rename"
    @State private var renameText = "Rename This"
    @FocusState private var isFocused: Bool
    @State private var editMode = false
    @State var viewModel = SnippetViewModel()
    
    var headerSection: some View {
        HStack {
            Text("hello")
//            Spacer()
        }
    }
    
    var body: some View {
        Text("Press the edit button to delete any tags")
            .foregroundColor(.secondary)
            .font(.custom("IBMPlexMono-Regular", size: 12))
        
        Form {
            Section() {
                List {
                    ForEach(tags, id: \.self) { tag in
                        HStack(alignment: .center){
                            Label("\(tag.name ?? "")", systemImage: (tag.imageTag!.isEmpty ? "tag.fill" : tag.imageTag) ?? "tag.fill")
                                .foregroundStyle(Color.label)
                        }
                        
                    }
                    .onDelete(perform: { indexSet in
                        self.handleDeleteTags(offsets: indexSet)
                    })
                    
                }
            }
            
           
        }
        .navigationTitle("Tags")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarItems(trailing: EditButton())
        .environment(\.editMode, self.$isEditMode)
        .onAppear() {
            viewModel.modelContext = modelContext
        }

     
     
        

    }
    
    func handleDeleteTags(offsets: IndexSet) {
        viewModel.deleteTag(offsets: offsets, tags: tags)
    }
}

#Preview {
    let container = SnipKeyDataManager().makeSharedContainer()
    
    return TagsView()
        .modelContainer(container)
}
