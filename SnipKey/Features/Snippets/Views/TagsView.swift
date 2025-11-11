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
    @Query(sort: \SnipTag.name) private var tags: [SnipTag]
    
    @State var isEditMode: EditMode = .inactive
  
    @State private var navigationTitletext = "Rename"
    @State private var renameText = "Rename This"
    @FocusState private var isFocused: Bool
    @State private var editMode = false
    @State var viewModel = SnippetViewModel()
    
    @State private var isEditTagVisible: Bool = false
    @State private var selectedTag: SnipTag? = nil
    
    // States for creating new tags
    @State private var showCreateTagSheet = false
    @State private var newTagName = ""
    @State private var newTagIcon = "tag.fill"
    
    var body: some View {
        VStack {
            if tags.isEmpty {
                ContentUnavailableView(
                    "No Tags Yet",
                    systemImage: "tag.slash",
                    description: Text("Create your first tag to organize your snippets")
                )
            } else {
                Text("Press the edit button to delete any tags")
                    .foregroundColor(.secondary)
                    .font(.custom("IBMPlexMono-Regular", size: 12))
                
                Form {
                    Section {
                        List {
                            ForEach(tags, id: \.self) { tag in
                                HStack(alignment: .center) {
                                    Label(
                                        "\(tag.name ?? "")",
                                        systemImage: (tag.imageTag!.isEmpty ? "tag.fill" : tag.imageTag) ?? "tag.fill"
                                    )
                                    .foregroundStyle(Color.label)
                                    
                                    Spacer()
                                    
                                    Button {
                                        selectedTag = tag
                                    } label: {
                                        Image(systemName: "applepencil.gen1")
                                            .padding(6)
                                            .background(.thickMaterial)
                                            .clipShape(.rect(cornerRadius: 4))
                                    }
                                    .pressable()
                                }
                            }
                            .onDelete(perform: { indexSet in
                                self.handleDeleteTags(offsets: indexSet)
                            })
                        }
                    }
                }
            }
        }
        .sheet(item: $selectedTag) { selected in
            EditTagView(tag: .constant(selected))
        }
        .sheet(isPresented: $showCreateTagSheet) {
            CreateTagSheet(
                tagName: $newTagName,
                tagIcon: $newTagIcon,
                onSave: {
                    createNewTag()
                }
            )
            .presentationDetents([.height(300)])
            .presentationDragIndicator(.visible)
        }
        .navigationTitle("Tags")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showCreateTagSheet = true
                } label: {
                    Label("Create Tag", systemImage: "plus.circle.fill")
                        .font(.custom("IBMPlexMono-Medium", size: 15))
                }
            }
            
            ToolbarItem(placement: .topBarTrailing) {
                EditButton()
            }
        }
        .environment(\.editMode, self.$isEditMode)
        .onAppear {
            viewModel.modelContext = modelContext
        }
    }
    
    private func createNewTag() {
        guard !newTagName.isEmpty else { return }
        
        // Check if tag already exists
        let tagExists = tags.contains { $0.name == newTagName }
        
        if !tagExists {
            let newTag = SnipTag(name: newTagName, imageTag: newTagIcon)
            modelContext.insert(newTag)
            
            // Save context
            do {
                try modelContext.save()
            } catch {
                print("Error saving new tag: \(error)")
            }
        }
        
        // Reset form
        newTagName = ""
        newTagIcon = "tag.fill"
        showCreateTagSheet = false
    }
    
    func handleDeleteTags(offsets: IndexSet) {
        viewModel.deleteTag(offsets: offsets, tags: tags)
    }
}

#Preview {
    let container = SnipKeyDataManager().makeSharedContainer()
    
    return NavigationStack {
        TagsView()
            .modelContainer(container)
    }
}
