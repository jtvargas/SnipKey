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
    @State private var newTagColorHex: String? = nil

    // Tag name search
    @State private var searchText = ""

    /// Tags in user-defined order, narrowed by the search query (case/diacritic-insensitive).
    private var filteredTags: [SnipTag] {
        let ordered = tags.userOrdered
        guard !searchText.isEmpty else { return ordered }
        return ordered.filter {
            ($0.name ?? "").localizedStandardContains(searchText)
        }
    }
    
    var body: some View {
        VStack {
            if tags.isEmpty {
                ContentUnavailableView(
                    "No Tags Yet",
                    systemImage: "tag.slash",
                    description: Text("Create your first tag to organize your snippets")
                )
            } else {
                Text("Press the edit button to delete or re-arrange tags")
                    .foregroundColor(.secondary)
                    .font(.custom("IBMPlexMono-Regular", size: 12))
                
                Form {
                    Section {
                        List {
                            ForEach(filteredTags, id: \.self) { tag in
                                HStack(alignment: .center, spacing: 10) {
                                    TagColorIndicator(colorHex: tag.colorHex, size: 10)
                                    
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
                            // Reordering only makes sense against the full list — offsets
                            // from a search-narrowed list would scramble other tags.
                            .onMove(perform: searchText.isEmpty ? handleMoveTags : nil)
                        }
                    }
                }
                .overlay {
                    if !searchText.isEmpty && filteredTags.isEmpty {
                        ContentUnavailableView.search(text: searchText)
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
                tagColorHex: $newTagColorHex,
                onSave: {
                    createNewTag()
                }
            )
            .presentationDetents([.height(480)])
            .presentationDragIndicator(.visible)
        }
        .navigationTitle("Tags")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Search Tags"
        )
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
            let newTag = SnipTag(name: newTagName, imageTag: newTagIcon, colorHex: newTagColorHex)
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
        newTagColorHex = nil
        showCreateTagSheet = false
    }
    
    func handleDeleteTags(offsets: IndexSet) {
        // Offsets come from the ForEach over `filteredTags` — delete against the same array.
        viewModel.deleteTag(offsets: offsets, tags: filteredTags)
    }

    /// Persist a drag-reorder: apply the move to the full ordered list, then renumber
    /// every tag 0..n so the order is total (nil sortOrders become explicit) and the
    /// filter menu in Snippets renders the exact same sequence.
    func handleMoveTags(from source: IndexSet, to destination: Int) {
        var ordered = tags.userOrdered
        ordered.move(fromOffsets: source, toOffset: destination)
        for (index, tag) in ordered.enumerated() where tag.sortOrder != index {
            tag.sortOrder = index
        }
        try? modelContext.save()
    }
}

#Preview {
    let container = SnipKeyDataManager().makeSharedContainer()
    
    return NavigationStack {
        TagsView()
            .modelContainer(container)
    }
}
