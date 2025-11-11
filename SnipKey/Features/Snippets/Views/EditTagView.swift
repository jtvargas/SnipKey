//
//  EditTagView.swift
//  SnipKey
//
//  Created by Jonathan Taveras Vargas on 8/20/24.
//

import SwiftUI
import SymbolPicker

struct EditTagView: View {
    @Binding var tag: SnipTag
    @Environment(\.dismiss) var dismiss
    
    @State private var tagName: String
    @State private var tagIcon: String
    @State private var isSymbolPickerPresented = false
    @State private var showDeleteConfirmation = false
    
    @Environment(\.modelContext) var modelContext
    
    init(tag: Binding<SnipTag>) {
        self._tag = tag
        _tagName = State(initialValue: tag.wrappedValue.name ?? "")
        _tagIcon = State(initialValue: tag.wrappedValue.imageTag ?? "tag.fill")
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    // Icon Picker
                    HStack {
                        Text("Icon")
                            .font(.custom("IBMPlexMono-Medium", size: 14))
                        Spacer()
                        Button {
                            isSymbolPickerPresented = true
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: tagIcon)
                                    .font(.title2)
                                    .foregroundStyle(Color.blue)
                                    .frame(width: 30)
                                Text("Change")
                                    .foregroundColor(.blue)
                                    .font(.custom("IBMPlexMono-Medium", size: 14))
                            }
                        }
                    }
                    
                    // Tag Name
                    HStack {
                        Text("Name")
                            .font(.custom("IBMPlexMono-Medium", size: 14))
                        Spacer()
                        TextField("Tag name", text: $tagName)
                            .multilineTextAlignment(.trailing)
                            .textFieldStyle(.plain)
                            .disableAutocorrection(true)
                            .limitText($tagName, to: tagCharLimit)
                            .font(.custom("IBMPlexMono-Regular", size: 14))
                    }
                } header: {
                    Text("Tag Details")
                        .font(.custom("IBMPlexMono-Bold", size: 12))
                } footer: {
                    HStack {
                        Text("Characters: \(tagName.count)/\(tagCharLimit)")
                            .font(.custom("IBMPlexMono-Regular", size: 10))
                        Spacer()
                    }
                }
                
                // Tag Preview Section
                Section {
                    HStack {
                        Spacer()
                        VStack(spacing: 12) {
                            Text("Preview")
                                .font(.custom("IBMPlexMono-Medium", size: 12))
                                .foregroundColor(.secondary)
                            
                            Label(tagName.isEmpty ? "Tag Name" : tagName, systemImage: tagIcon)
                                .font(.custom("IBMPlexMono-Medium", size: 16))
                                .foregroundStyle(tagName.isEmpty ? Color.secondary : Color.label)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .background(Color.secondarySystemBackground)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                }
                
                // Snippets using this tag
                if let snippetCount = tag.snippets?.count, snippetCount > 0 {
                    Section {
                        HStack {
                            Image(systemName: "doc.text.fill")
                                .foregroundColor(.secondary)
                            Text("\(snippetCount) snippet\(snippetCount == 1 ? "" : "s") using this tag")
                                .font(.custom("IBMPlexMono-Regular", size: 13))
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                // Delete Section
                Section {
                    Button(role: .destructive) {
                        showDeleteConfirmation = true
                    } label: {
                        HStack {
                            Spacer()
                            Label("Delete Tag", systemImage: "trash.fill")
                                .font(.custom("IBMPlexMono-Medium", size: 14))
                                .tint(.red)
                            Spacer()
                        }
                    }
                } footer: {
                    if let snippetCount = tag.snippets?.count, snippetCount > 0 {
                        Text("Deleting this tag will not delete the snippets using it.")
                            .font(.custom("IBMPlexMono-Regular", size: 10))
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Edit Tag")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .font(.custom("IBMPlexMono-Medium", size: 15))
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveChanges()
                    }
                    .disabled(tagName.isEmpty || tagName == tag.name && tagIcon == tag.imageTag)
                    .bold()
                    .font(.custom("IBMPlexMono-Medium", size: 15))
                }
            }
            .sheet(isPresented: $isSymbolPickerPresented) {
                SymbolPicker(symbol: $tagIcon)
            }
            .alert("Delete Tag?", isPresented: $showDeleteConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) {
                    deleteTag()
                }
            } message: {
                if let snippetCount = tag.snippets?.count, snippetCount > 0 {
                    Text("This tag is used by \(snippetCount) snippet\(snippetCount == 1 ? "" : "s"). The snippets will not be deleted.")
                } else {
                    Text("Are you sure you want to delete this tag?")
                }
            }
        }
    }
    
    private func saveChanges() {
        guard !tagName.isEmpty else { return }
        
        // Check if anything actually changed
        if tagName != tag.name || tagIcon != tag.imageTag {
            tag.name = tagName
            tag.imageTag = tagIcon
            
            // Save context
            do {
                try modelContext.save()
            } catch {
                print("Error saving tag changes: \(error)")
            }
        }
        
        dismiss()
    }
    
    private func deleteTag() {
        modelContext.delete(tag)
        
        do {
            try modelContext.save()
        } catch {
            print("Error deleting tag: \(error)")
        }
        
        dismiss()
    }
}

#Preview {
    let container = SnipKeyDataManager().makeSharedContainer()
    let tag = SnipTag(name: "Sample Tag", imageTag: "star.fill")
    
    return EditTagView(tag: .constant(tag))
        .modelContainer(container)
}
