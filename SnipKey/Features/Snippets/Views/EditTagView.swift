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
    
    init(tag: Binding<SnipTag>) {
        self._tag = tag
        _tagName = State(initialValue: tag.wrappedValue.name ?? "")
        _tagIcon = State(initialValue: tag.wrappedValue.imageTag ?? "tag.fill")
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Button(action: {
                    isSymbolPickerPresented = true
                }) {
                    Image(systemName: tagIcon)
                        .font(.system(size: 50))
                        .frame(width: 80, height: 80)
                        .background(Color.secondary.opacity(0.2))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .sheet(isPresented: $isSymbolPickerPresented) {
                    SymbolPicker(symbol: $tagIcon)
                }
                
                TextField("Tag Name", text: $tagName)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .padding(.horizontal)
                
                Spacer()
            }
            .padding()
            .navigationTitle("Edit Tag")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        saveChanges()
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func saveChanges() {
        tag.name = tagName
        tag.imageTag = tagIcon
    }
}


#Preview {
    let tag = SnipTag(name: "Sample Tag", imageTag: "star.fill")
    return EditTagView(tag: .constant(tag))
}
