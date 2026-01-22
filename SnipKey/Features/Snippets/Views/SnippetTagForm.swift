//
//  SnippetTagForm.swift
//  SnipKey
//
//  Created by Jonathan Taveras Vargas on 11/7/25.
//

import SwiftUI
import SymbolPicker
import SwiftData

struct CreateOrSelectTag: View {
    @Binding var snippetTag: SnipTag
    
    @State private var showCreateTagSheet = false
    @State private var newTagName = ""
    @State private var newTagIcon = "tag.fill"
    @State private var newTagColorHex: String? = nil
    @State private var iconPickerPresented = false
    
    @Environment(\.modelContext) var modelContext
    @Query(sort: \SnipTag.name) private var tags: [SnipTag]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Tag Selection Menu
            if tags.isEmpty {
                Button {
                    showCreateTagSheet = true
                } label: {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                        Text("Create Your First Tag")
                        Spacer()
                        Image(systemName: "chevron.right")
                    }
                    .foregroundColor(.accentColor)
                }
            } else {
                // Selected Tag Display or Picker
                Menu {
                    // None/Clear Option
                    Button {
                        snippetTag = SnipTag(name: "", imageTag: "tag.fill")
                    } label: {
                        Label("None", systemImage: "tag.slash.fill")
                    }
                    
                    Divider()
                    
                    // Existing Tags
                    ForEach(tags, id: \.id) { tag in
                        Button {
                            snippetTag = tag
                        } label: {
                            Label(tag.name ?? "", systemImage: tag.imageTag ?? "tag.fill")
                        }
                    }
                    
                    Divider()
                    
                    // Create New Tag Option
                    Button {
                        showCreateTagSheet = true
                    } label: {
                        Label("Create New Tag", systemImage: "plus.circle.fill")
                    }
                } label: {
                    HStack {
                        Image(systemName: snippetTag.name?.isEmpty == false ? (snippetTag.imageTag ?? "tag.fill") : "tag.slash.fill")
                            .foregroundStyle(snippetTag.name?.isEmpty == false ? Color.label : Color.secondary)
                        
                        Text(snippetTag.name?.isEmpty == false ? snippetTag.name! : "Select Tag")
                            .foregroundColor(snippetTag.name?.isEmpty == false ? Color.label : Color.secondary)
                        
                        Spacer()
                        
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 8)
                }
            }
        }
        .sheet(isPresented: $showCreateTagSheet) {
            CreateTagSheet(
                tagName: $newTagName,
                tagIcon: $newTagIcon,
                tagColorHex: $newTagColorHex,
                onSave: {
                    createAndSelectTag()
                }
            )
            .presentationDetents([.height(480)])
            .presentationDragIndicator(.visible)
        }
    }
    
    private func createAndSelectTag() {
        guard !newTagName.isEmpty else { return }
        
        // Check if tag already exists
        if let existingTag = tags.first(where: { $0.name == newTagName }) {
            snippetTag = existingTag
        } else {
            // Create new tag
            let newTag = SnipTag(name: newTagName, imageTag: newTagIcon, colorHex: newTagColorHex)
            modelContext.insert(newTag)
            snippetTag = newTag
        }
        
        // Reset form
        newTagName = ""
        newTagIcon = "tag.fill"
        newTagColorHex = nil
        showCreateTagSheet = false
    }
}

// Separate sheet for creating tags
struct CreateTagSheet: View {
    @Binding var tagName: String
    @Binding var tagIcon: String
    @Binding var tagColorHex: String?
    var onSave: () -> Void
    
    @State private var iconPickerPresented = false
    @Environment(\.dismiss) var dismiss
    
    // Convenience initializer for backward compatibility
    init(tagName: Binding<String>, tagIcon: Binding<String>, tagColorHex: Binding<String?> = .constant(nil), onSave: @escaping () -> Void) {
        self._tagName = tagName
        self._tagIcon = tagIcon
        self._tagColorHex = tagColorHex
        self.onSave = onSave
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    // Icon Picker
                    HStack {
                        Text("Icon")
                        Spacer()
                        Button {
                            iconPickerPresented = true
                        } label: {
                            HStack {
                                Image(systemName: tagIcon)
                                    .font(.title2)
                                    .foregroundStyle(Color.yellow)
                                Text("Choose")
                                    .foregroundColor(.yellow)
                            }
                        }
                    }
                    
                    // Tag Name
                    HStack {
                        Text("Name")
                        Spacer()
                        TextField("Tag name", text: $tagName)
                            .multilineTextAlignment(.trailing)
                            .textFieldStyle(.plain)
                            .disableAutocorrection(true)
                            .limitText($tagName, to: tagCharLimit)
                    }
                } header: {
                    Text("Tag Details")
                } footer: {
                    Text("Characters: \(tagName.count)/\(tagCharLimit)")
                        .font(.caption)
                }
                
                // Color Picker Section
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Color")
                            Spacer()
                            if let hex = tagColorHex {
                                HStack(spacing: 6) {
                                    Circle()
                                        .fill(Color(hex: hex) ?? .gray)
                                        .frame(width: 16, height: 16)
                                    Text(TagColor.from(hex: hex)?.displayName ?? "Custom")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            } else {
                                Text("None")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        TagColorPicker(selectedColorHex: $tagColorHex)
                    }
                } header: {
                    Text("Tag Color")
                }
            }
            .navigationTitle("Create Tag")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        tagName = ""
                        tagIcon = "tag.fill"
                        tagColorHex = nil
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        onSave()
                    }
                    .disabled(tagName.isEmpty)
                    .bold()
                }
            }
            .sheet(isPresented: $iconPickerPresented) {
                SymbolPicker(symbol: $tagIcon)
            }
        }
    }
}



// This sheet is used when multiple snippets are selected
// and is a sheet to select the tag you want to move the snippets or create a new one to be added
struct MoveOrCreateTagSheet: View {
    @Binding var snippetsSelection: Set<SnippetItem>
    @State private var selectedTag: SnipTag?
    @State private var isCreatingNewTag = false
    @State private var newTagName = ""
    @State private var newTagIcon = "tag.fill"
    @State private var newTagColorHex: String? = nil
    @State private var iconPickerPresented = false
    
    @Environment(\.dismiss) var dismiss
    @Environment(\.modelContext) var modelContext
    @Query(sort: \SnipTag.name) private var tags: [SnipTag]
    
    var onSave: () -> Void
    
    var body: some View {
        NavigationStack {
            Form {
                // Tag Selection Section
                Section {
                    if !isCreatingNewTag {
                        // Existing Tags List
                        ForEach(tags, id: \.id) { tag in
                            HStack {
                                TagColorIndicator(colorHex: tag.colorHex, size: 10)
                                Image(systemName: tag.imageTag ?? "tag.fill")
                                    .foregroundStyle(Color.accentColor)
                                Text(tag.name ?? "")
                                Spacer()
                                if selectedTag?.id == tag.id {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.accentColor)
                                }
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedTag = tag
                            }
                        }
                        
                        // Create New Tag Button
                        Button {
                            isCreatingNewTag = true
                        } label: {
                            HStack {
                                Image(systemName: "plus.circle.fill")
                                Text("Create New Tag")
                                Spacer()
                            }
                            .foregroundColor(.accentColor)
                        }
                    }
                } header: {
                    HStack {
                        Text("Select Tag")
                        Spacer()
                        if isCreatingNewTag {
                            Button("Cancel") {
                                isCreatingNewTag = false
                                newTagName = ""
                                newTagIcon = "tag.fill"
                                newTagColorHex = nil
                            }
                            .font(.caption)
                        }
                    }
                } footer: {
                    Text("\(snippetsSelection.count) snippet(s) will be moved")
                        .font(.caption)
                }
                
                // Create New Tag Section
                if isCreatingNewTag {
                    Section {
                        // Icon Picker
                        HStack {
                            Text("Icon")
                            Spacer()
                            Button {
                                iconPickerPresented = true
                            } label: {
                                HStack {
                                    Image(systemName: newTagIcon)
                                        .font(.title2)
                                        .foregroundStyle(Color.accentColor)
                                    Text("Choose")
                                        .foregroundColor(.accentColor)
                                }
                            }
                        }
                        
                        // Tag Name
                        HStack {
                            Text("Name")
                            Spacer()
                            TextField("Tag name", text: $newTagName)
                                .multilineTextAlignment(.trailing)
                                .textFieldStyle(.plain)
                                .disableAutocorrection(true)
                                .limitText($newTagName, to: tagCharLimit)
                        }
                    } header: {
                        Text("New Tag Details")
                    } footer: {
                        Text("Characters: \(newTagName.count)/\(tagCharLimit)")
                            .font(.caption)
                    }
                    
                    // Color Picker Section
                    Section {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Color")
                                Spacer()
                                if let hex = newTagColorHex {
                                    HStack(spacing: 6) {
                                        Circle()
                                            .fill(Color(hex: hex) ?? .gray)
                                            .frame(width: 16, height: 16)
                                        Text(TagColor.from(hex: hex)?.displayName ?? "Custom")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                } else {
                                    Text("None")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            
                            TagColorPicker(selectedColorHex: $newTagColorHex)
                        }
                    } header: {
                        Text("Tag Color")
                    }
                }
            }
            .navigationTitle("Move to Tag")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onMoveSnippetsSelectedToTag()
                    }
                    .disabled(shouldDisableSaveButton())
                    .bold()
                }
            }
            .sheet(isPresented: $iconPickerPresented) {
                SymbolPicker(symbol: $newTagIcon)
            }
        }
    }
    
    private func shouldDisableSaveButton() -> Bool {
        if isCreatingNewTag {
            return newTagName.isEmpty
        }
        return selectedTag == nil
    }
    
    private func onMoveSnippetsSelectedToTag() {
        var targetTag: SnipTag?
        
        if isCreatingNewTag {
            // Check if tag already exists
            if let existingTag = tags.first(where: { $0.name == newTagName }) {
                targetTag = existingTag
            } else {
                // Create new tag
                let newTag = SnipTag(name: newTagName, imageTag: newTagIcon, colorHex: newTagColorHex)
                modelContext.insert(newTag)
                targetTag = newTag
            }
        } else {
            targetTag = selectedTag
        }
        
        // Apply tag to all selected snippets
        if let tag = targetTag {
            for snippet in snippetsSelection {
                snippet.customTag = tag
            }
            
            // Save context
            do {
                try modelContext.save()
            } catch {
                print("Error saving: \(error)")
            }
        }
        
        dismiss()
        onSave()
    }
}
