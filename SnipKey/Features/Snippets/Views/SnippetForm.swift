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
import PhotosUI

struct CustomRadioButtonGroup<T: Hashable>: View {
    let items: [T]
      @Binding var selection: T
      let labels: [T: String]
      let disabledItems: Set<T>  // New parameter to specify disabled items
      
      private let columns = 3
      
      init(items: [T], selection: Binding<T>, labels: [T: String], disabledItems: Set<T> = []) {
          self.items = items
          self._selection = selection
          self.labels = labels
          self.disabledItems = disabledItems
      }
      
      var body: some View {
          ScrollView {
              VStack(spacing: 20) {
                  ForEach(0..<rowCount, id: \.self) { rowIndex in
                      HStack(spacing: 20) {
                          ForEach(itemsForRow(rowIndex), id: \.self) { item in
                              radioButton(for: item)
                          }
                      }
                      .frame(maxWidth: .infinity, alignment: rowIndex == rowCount - 1 && lastRowItemCount < 3 ? .center : .leading)
                  }
              }
              .padding()
          }
      }
      
      private var rowCount: Int {
          (items.count + columns - 1) / columns
      }
      
      private var lastRowItemCount: Int {
          items.count % columns == 0 ? columns : items.count % columns
      }
      
      private func itemsForRow(_ row: Int) -> [T] {
          let startIndex = row * columns
          let endIndex = min(startIndex + columns, items.count)
          return Array(items[startIndex..<endIndex])
      }
      
      private func radioButton(for item: T) -> some View {
          Button(action: {
              if !disabledItems.contains(item) {
                  let impactMed = UIImpactFeedbackGenerator(style: .medium)
                  impactMed.impactOccurred()
                  self.selection = item
                  hideKeyboard()
              }
          }) {
              VStack {
                  SnippetImage(type: item as! SnipType)
                      .frame(width: 35, height: 35)
                      .background(
                          Color.secondarySystemBackground,
                          in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                      )
                      .foregroundStyle(disabledItems.contains(item) ? .gray : .white)
                  Text(self.labels[item] ?? "")
                      .foregroundColor(disabledItems.contains(item) ? .gray : (selection == item ? Color.label : .gray))
                  if selection == item && !disabledItems.contains(item) {
                      Circle()
                          .fill(Color.label)
                          .frame(width: 10, height: 10)
                  } else {
                      Circle()
                          .stroke(disabledItems.contains(item) ? Color.gray : Color.label, lineWidth: 1)
                          .frame(width: 10, height: 10)
                  }
              }
              .padding()
              .frame(width: 100)  // Adjust this value as needed
              .contentShape(Rectangle())
          }
          .buttonStyle(PlainButtonStyle())
          .overlay(
              selection == item && !disabledItems.contains(item)
              ? RoundedRectangle(cornerRadius: 8)
                  .stroke(Color.secondarySystemBackground, lineWidth: 4) : nil
          )
          .opacity(disabledItems.contains(item) ? 0.5 : 1.0)
          .disabled(disabledItems.contains(item))
      }
  }


let options: [SnipType] = [.txt, .url, .image, .file]
let labels: [SnipType: String] = [.txt: "text", .url: "url", .file: "pdf", .image: "image"]
let titleCharLimit = 24
let tagCharLimit = 18
enum Field {
    case snippetTitle
    case snippetContent
}

//struct CreateOrSelectTag: View {
//   
//    
//    @Binding var isCreatingNewTag: Bool
//    @Binding var snippetTag: SnipTag
//    
//    @State private var tempTagName = ""
//    @Binding var tagName: String
//    @Binding var tagIcon: String
//    
//    @State var selection: String = ""
//    @State private var iconPickerPresented = false
//    
//    @Environment(\.modelContext) var modelContext
//    @Query( sort: \SnipTag.name) private var tags: [SnipTag]
//    
//    
//    var body: some View {
//        let customTagNameBinding = Binding(
//            get: { snippetTag.name ?? "" }, // Default to false if nil
//            set: { newValue in snippetTag.name = newValue }
//        )
//        let customTagIconBinding = Binding(
//            get: { snippetTag.imageTag ?? "tag.fill" }, // Default to false if nil
//            set: { newValue in snippetTag.imageTag = newValue }
//        )
//        
//        Toggle("Create New Tag", isOn: $isCreatingNewTag)
//        
//        if isCreatingNewTag {
//            HStack {
//                Button {
//                    iconPickerPresented = true
//                } label: {
//                    HStack {
//                        Image(systemName: snippetTag.imageTag!)
//                            .tint(Color.label)
//                            .frame(width: 24, height: 24)
//                            .padding(10)  // Apply padding before the overlay and background to include it in the rounded shape
//                            .background(Color.secondarySystemBackground)  // Set the background color
//                            .clipShape(RoundedRectangle(cornerRadius: 6))  // Clip the background to a rounded rectangle
//                            .overlay(
//                                RoundedRectangle(cornerRadius: 6)
//                                    .stroke(Color.label, lineWidth: 2)
//                            )
//                    }
//                }
//                .sheet(isPresented: $iconPickerPresented) {
//                    SymbolPicker(symbol: customTagIconBinding)
//                }
//                Spacer()
//                
//                VStack(alignment: .leading) {
//                    TextField("Your Tag Name Here", text: customTagNameBinding)
//                        .disableAutocorrection(true)
//                        .limitText(customTagNameBinding, to: tagCharLimit)
//                    Text("Text Limit: \(tagCharLimit)")
//                        .font(.custom("IBMPlexMono-Regular", size: 10))
//                }
//                
//            }
//            .onAppear {
//                tempTagName = tagName
//                tagName = ""
//            }
//            .onDisappear {
//                tagName = tempTagName
//            }
//            
//        } else {
//            if tags.isEmpty {
//                Text("No tags available, create a new one")
//                    .foregroundColor(.secondary)
//                    .font(.custom("IBMPlexMono-Regular", size: 12))
//            } else {
//                Picker(selection: $snippetTag, label: Image(systemName: "tag.fill")) {
//                    ForEach(tags, id: \.id) { tag in
//                        HStack {
//                            Text(tag.name ?? "")
//                            Spacer()
//                            Image(systemName: tag.imageTag ?? "tag.fill")
//                        }
//                        .tag(tag)
//                    }
//                }
//                .pickerStyle(.menu)
//                .tint(Color.label)
//                .onTapGesture {
//                    let impactMed = UIImpactFeedbackGenerator(style: .medium)
//                    impactMed.impactOccurred()
//                }
//            }
//            
//        }
//    }
//}


struct SnippetForm: View {
    @Environment(\.colorScheme) var colorScheme
    
    let disabledItems: Set<SnipType> = []
    
    let snippet: SnippetItem?
    let deviceBiometrics: DeviceBiometrics = DeviceBiometrics()
    
    var isCreatingNewOne: Bool {
        return snippet == nil
    }
    
    private var editorTitle: String {
        isCreatingNewOne ? "Add Snippet" : "Edit Snippet"
    }
    
    @State private var type = SnipType.txt
    @State private var title = ""
    @State private var content = ""
    @State private var bulkContent: String = ""
    @State private var customTagName: String = ""
    @State private var customTagIconName: String = "tag.fill"
    
    @State private var snippetTag: SnipTag = SnipTag(name: "", imageTag: "tag.fill")
    
    //    Image File State
    @State var selectedImage: PhotosPickerItem?
    
    
    //    File State
    @State var contentFileData: Data?
    @State var contentFileFormatType: String?

    
    @FocusState private var focusedField: Field?
    @Binding var isFormVisible: Bool
    @State var isCreatingNewTag: Bool = false
    @State var snippetViewModel = SnippetViewModel()
    
    @State var isSecure: Bool = false
    
    @Environment(\.modelContext) var modelContext
    //    @Query(sort: \SnipTag.name) private var tags: [SnipTag]
    
    //bulk creation
    @State private var isCreatingSnippets = false
    @State private var currentProgress = 0
    @State private var totalSnippets = 0
    @State private var showSuccessToast = false
    @State private var formCreation = 0
    var isBulkCreation: Bool {
        formCreation == 1
    }
    

    
    var bulkSnippetsToCreateCount: Int {
        bulkContent.split(separator: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .count
    }
    


    var body: some View {
        NavigationStack {
            ZStack {
                VisualEffectView(effect: UIBlurEffect(style: colorScheme == .dark ? .dark : .light))
                    .edgesIgnoringSafeArea(.all)
                
                
                VStack {
                    if isCreatingNewOne {
                        Picker("What is your favorite color?", selection: $formCreation) {
                            Text("Single").tag(0)
                            Text("Bulk").tag(1)
                        }
                        .padding()
                        .pickerStyle(.segmented)
                    } else {
                        Label("Don't forget to click Save!", systemImage: "info.square.fill")
                            .bold()
                            .font(.custom("IBMPlexMono-Medium", size: 15))
                    }
                    
                    if formCreation == 0 {
                        SingleSnippetFormView()
                    } else {
                        BulkSnippetFormView()
                    }
                   
                    
                    

                   
                }
                
                // Progress overlay
                ProgressOverlay()
                
                // Success toast
                SuccessToast()
            }
        }
        .presentationBackground(Color.clear)
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
                    hideKeyboard()
                }
                .font(.custom("IBMPlexMono-Bold", size: 14))
                .tint(Color.black)

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
                .disabled(getDisabledSaveAction())
            }
        }
        .onAppear {
            snippetViewModel.modelContext = modelContext
            if let snippet {
                title = snippet.title!
                content = snippet.content!
                type = snippet.type!
                isSecure = snippet.isSecure
                contentFileData = snippet.file?.fileData
                customTagName = snippet.customTag?.name ?? ""
                customTagIconName = snippet.customTag?.imageTag ?? "tag.fill"
                snippetTag = snippet.customTag ?? SnipTag(name: "", imageTag: "tag.fill")
            }
        }
        .onChange(of: type) { oldType , newType in
            switch newType {
            case .txt:
                content = ""
                contentFileData = nil
            case .url:
                content = ""
                contentFileData = nil
            case .image:
                if oldType == .file {
                    contentFileData = nil
                    if let snippetFileId = snippet?.file?.id {
                        print("Delete Snippet FILE ID: \(snippetFileId)")
                        snippetViewModel.deleteFile(fileId: snippetFileId)
                    }
                }
                break
            case .file:
                // If changing from image to file, clear the image data
                if oldType == .image {
                    contentFileData = nil
                    if let snippetFileId = snippet?.file?.id {
                        print("Delete Snippet FILE ID: \(snippetFileId)")
                        snippetViewModel.deleteFile(fileId: snippetFileId)
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    func BulkSnippetFormView() -> some View {
        Form {
            Section(
                header: Text("Tag"),
                footer: Label(
                    "All snippets will be organized under this tag",
                    systemImage: "info.circle"
                )
            ) {
                CreateOrSelectTag(snippetTag: $snippetTag)
            }
            .listRowBackground(EmptyView().background(Color.tertiarySystemBackground))
            
            Section(
                header: VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Snippets")
                                .font(.headline)
                            Text("Each line becomes a new snippet")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .textCase(nil)
                        }
                        Spacer()
                            Button(action: pasteBulkContentFromClipboard) {
                                Label("Paste", systemImage: "doc.on.clipboard.fill")
                                    .tint(.label)
                                    .bold()
                                    .font(.custom("IBMPlexMono-Medium", size: 14))
                                    .underline()
                                    .tint(Color.label)
                            }
                    }
                    

                }
                .textCase(nil),
                footer: Text("\(bulkSnippetsToCreateCount) snippet\(bulkSnippetsToCreateCount == 1 ? "" : "s") will be created")
            ) {
                ZStack(alignment: .topLeading) {
                    if bulkContent.isEmpty {
                        Text("Add here one snippet per line...\n\nExample:\nHello World\nLorem ipsum\nKaomoji\n٩(ˊᗜˋ*)و ♡")
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 16)
                    }
                    
                    TextEditor(text: $bulkContent)
                        .frame(height: 220)
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .opacity(bulkContent.isEmpty ? 0.5 : 1)
                }
            }
            .listRowBackground(Color.tertiarySystemBackground)
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
        }
    }
    
    @ViewBuilder
    func SingleSnippetFormView() -> some View {
        Form {
            Section(
                header: Label(
                    "Security",
                    systemImage: "lock.fill"
                ),
                footer: Text(
                    "Enabling this will safeguard your snippet with FaceID/TouchID for secure access."
                )
            ) {
                Toggle(
                    "Sensitive Data",
                    isOn: $isSecure
                )
                .disabled(
                    !deviceBiometrics.hasBiometricsCapability
                )
            }
            .listRowBackground(EmptyView().background(Color.tertiarySystemBackground))
            
            Section(header: Text("snippet type")) {
                CustomRadioButtonGroup(items: options, selection: $type, labels: labels,  disabledItems: disabledItems)
                
            }
            .listRowBackground(EmptyView().background(Color.tertiarySystemBackground))
            
            Section(
                header: Text("snippet title *"),
                footer: HStack{
                    if title.count > (titleCharLimit / 2) {
                            footer
                    }
                    
                }
            ) {
                TextField("Title", text: $title)
                    .disableAutocorrection(true)
                    .focused($focusedField, equals: .snippetTitle)
                    .submitLabel(.return)
                    .limitText($title, to: titleCharLimit)
                
                
            }
            .listRowBackground(EmptyView().background(Color.tertiarySystemBackground))
            
            Section(header: HStack {
                Group{
                    Text("snippet content")
                    
                    Spacer()
                    if type == .txt || type == .url {
                        Button(action: pasteContentFromClipboard) {
                            Label("Paste", systemImage: "doc.on.clipboard.fill")
                                .tint(.label)
                                .bold()
                                .font(.custom("IBMPlexMono-Medium", size: 14))
                                .underline()
                                .tint(Color.label)
                        }
                    }
                    
                    
                    
                }
            }, footer: VStack {
                if !isKeyboardExtensionEnabled() && (type == .image || type == .file){
                    KeyboardAccessWarning()
                }
            }) {
                SnippetContentForm(
                    type: type,
                    contentValue: $content,
                    contentData: $contentFileData,
                    selectedImage: $selectedImage,
                    selectedFileMimeType: $contentFileFormatType
                )
                
            }
            .listRowBackground(EmptyView().background(Color.tertiarySystemBackground))
            
                           
            
            Section(
                header: Text("tag"),
                footer: Label(
                    "Categorize your snippets for easy access",
                    systemImage: "questionmark.circle"
                )
            ) {
                CreateOrSelectTag(snippetTag: $snippetTag)
            }
            .listRowBackground(EmptyView().background(Color.tertiarySystemBackground))
        }
    }
    
    @ViewBuilder
    func SuccessToast() -> some View {
        if showSuccessToast {
            VStack {
                Spacer()
                
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.title2)
                    
                    Text("\(totalSnippets) snippet\(totalSnippets == 1 ? "" : "s") created")
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
                .padding()
                .background(Color(uiColor: .systemBackground))
                .cornerRadius(12)
                .shadow(radius: 10)
                .padding(.bottom, 50)
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .animation(.spring(), value: showSuccessToast)
        }
    }
    
    @ViewBuilder
    func ProgressOverlay() -> some View {
        if isCreatingSnippets {
            ZStack {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                
                VStack(spacing: 20) {
                    ZStack {
                        Circle()
                            .stroke(Color.gray.opacity(0.3), lineWidth: 8)
                            .frame(width: 80, height: 80)
                        
                        Circle()
                            .trim(from: 0, to: CGFloat(currentProgress) / CGFloat(totalSnippets))
                            .stroke(Color.blue, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                            .frame(width: 80, height: 80)
                            .rotationEffect(.degrees(-90))
                            .animation(.linear(duration: 0.3), value: currentProgress)
                        
                        Text("\(currentProgress)")
                            .font(.title2)
                            .fontWeight(.semibold)
                    }
                    
                    VStack(spacing: 4) {
                        Text("Creating Snippets...")
                            .font(.headline)
                        Text("\(currentProgress) of \(totalSnippets)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(32)
                .background(Color(uiColor: .systemBackground))
                .cornerRadius(16)
                .shadow(radius: 20)
            }
        }
    }
    
    private var footer: some View {
        HStack {
            Text("Remaining: ")
            ZStack {
                Circle()
                    .stroke(Color.tertiaryLabel, lineWidth: 5)
                Text("\(titleCharLimit - title.count)")
                    .font(.custom("IBMPlexMono-Medium", size: 10))
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke((titleCharLimit - title.count) < titleCharLimit / 4 ? Color.red.gradient : Color.label.gradient, lineWidth: 5)
                    .rotationEffect(.init(degrees: -90))
            }
            .frame(width: 20, height: 20)
        }
        .transition(.opacity) // Add transition effect
    }
    
    var progress: CGFloat {
        return max(min(CGFloat(title.count) / CGFloat(titleCharLimit), 1), 0)
    }
    
    func toggleFormVisibility() {
        isFormVisible.toggle()
    }
    
    func pasteContentFromClipboard(){
        content = "\(content)\(pasteFromClipboard())"
    }
    
    func pasteBulkContentFromClipboard(){
        bulkContent = "\(bulkContent)\(pasteFromClipboard())"
    }
    
    func getDisabledSaveAction() -> Bool {
        let needNewTagName = isCreatingNewTag ? snippetTag.name!.isEmpty : false
        
        switch type {
        case .image, .file:
            return title.isEmpty || ((contentFileData?.isEmpty) != false) || needNewTagName
        case .txt, .url:
            return isBulkCreation ? bulkSnippetsToCreateCount == 0 : title.isEmpty || content.isEmpty || needNewTagName
        default:
            return false
        }
        
    }
    
    func getBulkSnippetsToSnippetItems() -> [SnippetItem] {
        let snippetItems: [SnippetItem] = bulkContent
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .map { content in
                let title = content.count > titleCharLimit
                    ? String(content.prefix(titleCharLimit)) + "..."
                    : String(content)
                
                return SnippetItem(
                    title: title,
                    content: content,
                    type: .txt,
                    isSecure: false
                )
            }
        
        return snippetItems
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
        // Only add tag if one is selected (not empty)
        guard let tagName = snippetTag.name, !tagName.isEmpty else {
            item.customTag = nil
            return
        }
        
        // Check if this is an existing tag or needs to be created
        if snippetTag.id == nil || modelContext.model(for: snippetTag.id) == nil {
            // Create new tag
            let newTag = SnipTag(name: tagName, imageTag: snippetTag.imageTag ?? "tag.fill")
            modelContext.insert(newTag)
            item.customTag = newTag
        } else {
            // Use existing tag
            item.customTag = snippetTag
        }
    }
    
    func addFileToSnippeet(item: SnippetItem) {
        if contentFileData != nil &&  contentFileFormatType != nil {
            
            if let snippetFileId = item.file?.id {
                snippetViewModel.deleteFile(fileId: snippetFileId)
            }
            
            let newFile = snippetViewModel.createData(type: .image, data: contentFileData!, fileFormatType: contentFileFormatType!)
            newFile.snippet?.append(item)
            item.file = newFile
        }
        
    }
    
    private func saveBulk() {
        let snippetsToCreate = getBulkSnippetsToSnippetItems()
        
        guard !snippetsToCreate.isEmpty else { return }
        
        isCreatingSnippets = true
        currentProgress = 0
        totalSnippets = snippetsToCreate.count
        
        // Use Task for async execution with UI updates
        Task {
            for (index, snippet) in snippetsToCreate.enumerated() {
                let newSnippetCreated = snippetViewModel.createSnippet(
                    snippet.title!,
                    content: snippet.content!,
                    type: snippet.type,
                    isSecure: snippet.isSecure
                )
                
                addTagToSnippet(item: newSnippetCreated)
                
                if snippet.type == .image || snippet.type == .file {
                    addFileToSnippeet(item: newSnippetCreated)
                }
                
                // Update progress
                await MainActor.run {
                    currentProgress = index + 1
                }
                
                // Small delay for better UX (optional, adjust as needed)
                try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
            }
            
            // Show success and dismiss
            await MainActor.run {
                isCreatingSnippets = false
                showSuccessToast = true
            }
            
            // Dismiss after showing success
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
//            await MainActor.run {
//                dismiss()
//            }
        }
    }
    
    private func save() {
        CreateSnippetTip.alreadyDiscovered = true
        
        if getDisabledSaveAction() {
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
                
                if type == .image || type == .file  {
                    addFileToSnippeet(item: snippet)
                }
            } else {
                if isBulkCreation {
                    saveBulk()
                } else {
                    // Create
                    let newSnippetCreated = snippetViewModel.createSnippet(title, content: content, type: type, isSecure: isSecure)
                    addTagToSnippet(item: newSnippetCreated)
                    
                    if type == .image || type == .file {
                        addFileToSnippeet(item: newSnippetCreated)
                    }
                }
               
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
        SnippetForm(snippet: tempSnippet, isFormVisible: $value)
    }
}

#Preview {
    return SnippetFormBindingPreview()
}
