//
//  SnippetForm.swift
//  SnipKey
//
//  Created by Jonathan Taveras Vargas on 3/28/24.
//

import SwiftData
import SwiftUI
import SymbolPicker
import UIKit

func pasteFromClipboard() -> String {
    UIPasteboard.general.string ?? ""
}

struct CustomRadioButtonGroup<T: Hashable>: View {
    let items: [T]
    @Binding var selection: T
    let labels: [T: String]
    
    var body: some View {
        HStack {
            ForEach(items, id: \.self) { item in
                Button(action: {
                    let impactMed = UIImpactFeedbackGenerator(style: .medium)
                    impactMed.impactOccurred()
                    self.selection = item
                    hideKeyboard()
                }) {
                    VStack {
                        SnippetImage(type: item as! SnipType)
                            .frame(width: 35, height: 35)
                            .background(
                                Color.secondarySystemBackground,
                                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                            )
                            .foregroundStyle(.white)
                        Text(self.labels[item] ?? "")
                            .foregroundColor(selection == item ? Color.label : .gray)
                        if selection == item {
                            Circle()
                                .fill(Color.label)
                                .frame(width: 10, height: 10)
                        } else {
                            Circle()
                                .stroke(Color.label, lineWidth: 1)
                                .frame(width: 10, height: 10)
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .contentShape(Circle())
                    
                }
                .buttonStyle(PlainButtonStyle())
                .overlay(
                    /// apply a rounded border
                    selection == item
                    ? RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondarySystemBackground, lineWidth: 4) : nil
                )
                
            }
            
        }
    }
}

let options: [SnipType] = [.txt, .url]
let labels: [SnipType: String] = [.txt: "text", .url: "url"]
let charLimit = 12
let tagCharLimit = 10
enum Field {
    case snippetTitle
    case snippetContent
}

struct CreateOrSelectTag: View {
    @Binding var isCreatingNewTag: Bool
    
    @State private var tempTagName = ""
    @Binding var tagName: String
    @Binding var tagIcon: String
    
    @State var selection: String = ""
    @State private var iconPickerPresented = false
    
    @Environment(\.modelContext) var modelContext
    @Query(sort: \SnipTag.name) private var tags: [SnipTag]
    
    var body: some View {
        Toggle("Create New Tag", isOn: $isCreatingNewTag)
        
        if isCreatingNewTag {
            HStack {
                Button {
                    iconPickerPresented = true
                } label: {
                    HStack {
                        Image(systemName: tagIcon)
                            .tint(Color.label)
                            .frame(width: 24, height: 24)
                            .padding(10)  // Apply padding before the overlay and background to include it in the rounded shape
                            .background(Color.secondarySystemBackground)  // Set the background color
                            .clipShape(RoundedRectangle(cornerRadius: 6))  // Clip the background to a rounded rectangle
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color.label, lineWidth: 2)
                            )
                    }
                }
                .sheet(isPresented: $iconPickerPresented) {
                    SymbolPicker(symbol: $tagIcon)
                }
                Spacer()
                
                VStack(alignment: .leading) {
                    TextField("Your Tag Name Here", text: $tagName)
                        .limitText($tagName, to: tagCharLimit)
                    Text("Remaining: \(tagCharLimit - tagName.count)")
                        .font(.custom("IBMPlexMono-Regular", size: 10))
                }
                
            }
            .onAppear {
                tempTagName = tagName
                tagName = ""
            }
            .onDisappear {
                tagName = tempTagName
            }
            
        } else {
            Picker(selection: $tagName, label: Image(systemName: "tag.fill")) {
                ForEach(tags, id: \.id) { tag in
                    HStack {
                        Text(tag.name)
                        Spacer()
                        Image(systemName: tag.imageTag)
                    }
                    .tag(tag.name)
                }
            }
            .pickerStyle(.menu)
            .tint(Color.label)
            .onTapGesture {
                let impactMed = UIImpactFeedbackGenerator(style: .medium)
                impactMed.impactOccurred()
            }
        }
    }
}

struct SnippetForm: View {
    let snippet: SnippetItem?
    let deviceBiometrics: DeviceBiometrics = DeviceBiometrics()
    
    private var editorTitle: String {
        snippet == nil ? "Add Snippet" : "Edit Snippet"
    }
    
    @State private var type = SnipType.txt
    @State private var title = ""
    @State private var content = ""
    @State private var customTagName: String = "None"
    @State private var customTagIconName: String = "tag.fill"
    
    @FocusState private var focusedField: Field?
    @Binding var isFormVisible: Bool
    @State var isCreatingNewTag: Bool = false
    @State var snippetViewModel = SnippetViewModel()
    
    @State var isSecure: Bool = false
    
    @Environment(\.modelContext) var modelContext
    //    @Query(sort: \SnipTag.name) private var tags: [SnipTag]
    
    var body: some View {
        
        let disableSaveAction =
        isCreatingNewTag
        ? (customTagName.isEmpty || title.isEmpty || content.isEmpty)
        : title.isEmpty || content.isEmpty
        
        
        NavigationStack {
           
            Label("Don't forget to click Save!", systemImage: "info.square.fill")
                .bold()
                .font(.custom("IBMPlexMono-Medium", size: 15))
           
            Form {
                
                Section(header: Text("Access"), footer: Text("Snippet store sensitive data, and requires FaceID/TouchID to use them")) {
                    Toggle("Sensitive Data", isOn: $isSecure)
                        .disabled(!deviceBiometrics.hasBiometricsCapability)
                }
//                .onChange(of: isSecure){ _, state in
//                    if state {
//                      handleSecureSnippet()
//                    }
//                }
                .listRowBackground(EmptyView().background(Color.tertiarySystemBackground))
                
               
                Section(header: Text("snippet type")) {
                    CustomRadioButtonGroup(items: options, selection: $type, labels: labels)
                    
                }
                .listRowBackground(EmptyView().background(Color.tertiarySystemBackground))
                
                Section(
                    header: Text("snippet title *"),
                    footer: Text("Remaining: \(charLimit - title.count)")
                ) {
                    TextField("Title", text: $title)
                        .disableAutocorrection(true)
                        .focused($focusedField, equals: .snippetTitle)
                        .submitLabel(.return)
                        .limitText($title, to: charLimit)
                    
                }
                .listRowBackground(EmptyView().background(Color.tertiarySystemBackground))
                
                Section(header: HStack {
                    Group{
                        Text("snippet content")
                        
                        Spacer()
                        Button(action: pasteContentFromClipboard) {
                            Label("Paste", systemImage: "doc.on.clipboard.fill")
                                .tint(.label)
                                .bold()
                                .font(.custom("IBMPlexMono-Medium", size: 14))
                                .underline()
                                .tint(Color.label)
                        }
                        
                        
                    }
                }) {
                    if type == .url {
                        Group {
                            TextField("yoursite.com", text: $content, axis: .vertical)
                                .keyboardType(.URL)
                                .textContentType(.URL)
                                .textInputAutocapitalization(.never)
                                .focused($focusedField, equals: .snippetContent)
                                .submitLabel(.return)
                                .tint(Color.label)
                           
                            if content.isValidURL() {
                                Button {
                                    openURLContent()
                                } label:{
                                    Text("Open URL")
                                        .tint(Color.blue)
                                }
                            }
                           
                        }
                       
                    } else {
                        TextField("Content", text: $content, axis: .vertical)
                            .textInputAutocapitalization(.never)
                            .lineLimit(5...10)
                            .focused($focusedField, equals: .snippetContent)
                            .submitLabel(.return)
                    }
                    
                    
                }
                .listRowBackground(EmptyView().background(Color.tertiarySystemBackground))
                
                
                Section(
                    header: Text("tag"),
                    footer: Label(
                        "Categorize your snippets for easy access", systemImage: "questionmark.circle")
                ) {
                    
                    CreateOrSelectTag(
                        isCreatingNewTag: $isCreatingNewTag, tagName: $customTagName,
                        tagIcon: $customTagIconName)
                    
                }
                .listRowBackground(EmptyView().background(Color.tertiarySystemBackground))
                
                .onSubmit {
                    switch focusedField {
                    default:
                        print("SnippetContent")
                    }
                }
            }
        }
        .navigationTitle(editorTitle)
        .font(.custom("IBMPlexMono-Bold", size: 14))
        .navigationBarTitleDisplayMode(.inline)
        .interactiveDismissDisabled()
        .bold()
        .font(.custom("IBMPlexMono-Medium", size: 15))
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    focusedField = nil
                }
                .font(.custom("IBMPlexMono-Bold", size: 14))
                .tint(Color.black)
                .background(Color.customSecondary)
                .cornerRadius(40)
            }
            ToolbarItem(placement: .topBarLeading) {
                Button(action: onClosePress) {
                    Text("Close")
                        .tint(Color.label)
                        .bold()
                        .underline()
                        .font(.custom("IBMPlexMono-Medium", size: 15))
                }
            }
            
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: save) {
                    Text("Save")
                        .tint(Color.label)
                        .bold()
                        .underline()
                    
                        .font(.custom("IBMPlexMono-Medium", size: 15))
                }
                .disabled(disableSaveAction)
            }
        }
        .onAppear {
            snippetViewModel.modelContext = modelContext
            if let snippet {
                title = snippet.title
                content = snippet.content
                type = snippet.type
                isSecure = snippet.isSecure
                customTagName = snippet.customTag?.name ?? "None"
                customTagIconName = snippet.customTag?.imageTag ?? "tag.fill"
            }
        }
        .onChange(of: type) {_, _ in
            if type == .txt {
                content = ""
            }
          
        }
    }
    
    func toggleFormVisibility() {
        isFormVisible.toggle()
    }
    
    func pasteContentFromClipboard(){
        content = "\(content)\(pasteFromClipboard())"
    }
    
    func openURLContent() {
        if !content.isEmpty  && content.isValidURL(){
            UIApplication.shared.open(URL(string: content.getValidURLString())!)
        }
       
    }
    
    func onClosePress() {
        self.toggleFormVisibility()
    }
    
    func handleSecureSnippet(){
        deviceBiometrics.authenticate(successHandler: {
            // Handle successful authentication
            isSecure = true
            print("Biometrics successfull!")
        }, unSuccessHandler: { error in
            // Handle unsuccessful authentication or error
            isSecure = false
            if let error = error {
                print("Authentication failed with error: \(error.localizedDescription)")
            } else {
                print("Authentication failed")
            }
        })
    }
    
    func addTagToSnippet(item: SnippetItem) {
        let tagCreated = snippetViewModel.findTagCreated(tagName: customTagName)
        
        if tagCreated != nil {
            tagCreated?.snippets?.append(item)
        } else {
            let newTagCreated = snippetViewModel.createTag(
                name: customTagName, iconName: customTagIconName)
            newTagCreated.snippets?.append(item)
        }
    }
    
    private func save() {
        print("customTagName: \(customTagName)")
        if title.isEmpty || content.isEmpty {
            print("cant save empty")
        } else {
            if let snippet {
                // Edit
                snippet.title = title
                snippet.content = content
                snippet.type = type
                snippet.updatedDate = Date.now
                snippet.isSecure = isSecure
                addTagToSnippet(item: snippet)
            } else {
                // Create
                let newSnippetCreated = snippetViewModel.createSnippet(title, content: content, type: type, isSecure: isSecure)
                addTagToSnippet(item: newSnippetCreated)
            }
            toggleFormVisibility()
        }
        
    }
    
    
}

struct SnippetFormBindingPreview: View {
    @State private var value = false
    @State private var tempSnippet: SnippetItem = SnippetItem(
        title: "", content: "", type: SnipType.txt, isSecure: false)
    
    var body: some View {
        SnippetForm(snippet: nil, isFormVisible: $value)
    }
}

#Preview {
    return SnippetFormBindingPreview()
}
