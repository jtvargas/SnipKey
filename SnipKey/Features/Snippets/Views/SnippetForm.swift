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

// MARK: - Snippet Type Selector
struct SnippetTypeSelector: View {
    @Binding var selection: SnipType
    let disabledItems: Set<SnipType>

    var body: some View {
        VStack(spacing: 12) {
            // Segmented Picker with icons
            Picker("Snippet Type", selection: $selection) {
                ForEach(options, id: \.self) { type in
                    Image(systemName: type.snipTypeImage)
                        .tag(type)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: selection) { _, _ in
                let impactMed = UIImpactFeedbackGenerator(style: .light)
                impactMed.impactOccurred()
            }

            // Type label with icon below segmented control
            HStack(spacing: 6) {
                Image(systemName: selection.snipTypeImage)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.label)

                Text(selection.displayText)
                    .font(.custom("IBMPlexMono-Medium", size: 14))
                    .foregroundStyle(Color.label)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.secondarySystemBackground)
            .clipShape(Capsule())
            .animation(.easeInOut(duration: 0.2), value: selection)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Title Character Counter
struct TitleCharacterCounter: View {
    let title: String
    let limit: Int

    private var remaining: Int {
        limit - title.count
    }

    private var progress: CGFloat {
        CGFloat(title.count) / CGFloat(limit)
    }

    private var progressColor: Color {
        if remaining <= 5 {
            return .red
        } else if remaining <= limit / 4 {
            return .orange
        }
        return .secondary
    }

    var body: some View {
        HStack(spacing: 8) {
            // Progress ring
            ZStack {
                Circle()
                    .stroke(Color.tertiaryLabel.opacity(0.3), lineWidth: 3)

                Circle()
                    .trim(from: 0, to: min(progress, 1.0))
                    .stroke(progressColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.2), value: progress)
            }
            .frame(width: 16, height: 16)

            // Character count text
            Text("\(title.count)/\(limit)")
                .font(.custom("IBMPlexMono-Regular", size: 11))
                .foregroundStyle(progressColor)
                .monospacedDigit()

            Spacer()

            // Warning when near limit
            if remaining <= 5 && remaining > 0 {
                Text("\(remaining) left")
                    .font(.custom("IBMPlexMono-Medium", size: 10))
                    .foregroundStyle(.orange)
            } else if remaining == 0 {
                Label("Limit reached", systemImage: "exclamationmark.circle.fill")
                    .font(.custom("IBMPlexMono-Medium", size: 10))
                    .foregroundStyle(.red)
            }
        }
        .padding(.top, 4)
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

struct SnippetFormDraft {
    let type: SnipType
    let pasteClipboardOnAppear: Bool
    var initialTitle: String = ""
    var initialContent: String = ""
    var initialTag: SnipTag? = nil
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
    let initialDraft: SnippetFormDraft?
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
    @State private var isSecurityExpanded: Bool = false
    @State private var isApplyingInitialDraft = false

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

    init(
        snippet: SnippetItem?,
        initialDraft: SnippetFormDraft? = nil,
        isFormVisible: Binding<Bool>
    ) {
        self.snippet = snippet
        self.initialDraft = initialDraft
        self._isFormVisible = isFormVisible
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


                VStack(spacing: 0) {
                    // Creation mode picker (only for new snippets)
                    if isCreatingNewOne {
                        VStack(spacing: 8) {
                            Picker("Creation Mode", selection: $formCreation) {
                                Label("Single", systemImage: "doc")
                                    .tag(0)
                                Label("Bulk", systemImage: "doc.on.doc")
                                    .tag(1)
                            }
                            .pickerStyle(.segmented)
                            .padding(.horizontal)
                            .padding(.top, 12)

                            // Mode description
                            Text(formCreation == 0 ? "Create one snippet at a time" : "Create multiple snippets from a list")
                                .font(.custom("IBMPlexMono-Regular", size: 11))
                                .foregroundStyle(.secondary)
                        }
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
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button {
                    hideKeyboard()
                } label: {
                    Text("Done")
                        .font(.custom("IBMPlexMono-Bold", size: 14))
                        .foregroundStyle(Color.label)
                }
            }

            ToolbarItem(placement: .topBarLeading) {
                Button(action: onClosePress) {
                    Text("Cancel")
                        .font(.custom("IBMPlexMono-Medium", size: 15))
                        .foregroundStyle(Color.label)
                }
            }

            ToolbarItem(placement: .principal) {
                VStack(spacing: 2) {
                    Text(editorTitle)
                        .font(.custom("IBMPlexMono-Bold", size: 16))

                    // Editing badge for edit mode
                    if !isCreatingNewOne {
                        Text("Editing")
                            .font(.custom("IBMPlexMono-Medium", size: 10))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.2))
                            .foregroundStyle(.orange)
                            .clipShape(Capsule())
                    }
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button(action: save) {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 14))
                        Text("Save")
                            .font(.custom("IBMPlexMono-SemiBold", size: 15))
                    }
                    .foregroundStyle(getDisabledSaveAction() ? Color.secondary : Color.label)
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
                isSecurityExpanded = snippet.isSecure // Auto-expand security section if snippet is secure
                contentFileData = snippet.file?.fileData
                customTagName = snippet.customTag?.name ?? ""
                customTagIconName = snippet.customTag?.imageTag ?? "tag.fill"
                snippetTag = snippet.customTag ?? SnipTag(name: "", imageTag: "tag.fill")
            } else if let initialDraft {
                applyInitialDraft(initialDraft)
            }

            // Auto-focus the next useful field for new snippets
            if isCreatingNewOne && formCreation == 0 {
                let initialFocus: Field = initialDraft?.initialTitle.isEmpty == false ? .snippetContent : .snippetTitle
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    focusedField = initialFocus
                }
            }
        }
        .onChange(of: type) { oldType , newType in
            guard !isApplyingInitialDraft else { return }

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
            // MARK: - Tag Section
            Section {
                CreateOrSelectTag(snippetTag: $snippetTag)
            } header: {
                Label("Tag", systemImage: "tag")
                    .font(.custom("IBMPlexMono-SemiBold", size: 12))
                    .textCase(.uppercase)
            } footer: {
                Label("All snippets will be organized under this tag", systemImage: "info.circle")
                    .font(.custom("IBMPlexMono-Regular", size: 11))
                    .foregroundStyle(.secondary)
            }
            .listRowBackground(Color.tertiarySystemBackground.opacity(0.5))

            // MARK: - Bulk Content Section
            Section {
                ZStack(alignment: .topLeading) {
                    if bulkContent.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Enter one snippet per line...")
                                .foregroundStyle(.tertiary)

                            Text("Example:")
                                .font(.custom("IBMPlexMono-Medium", size: 12))
                                .foregroundStyle(Color.quaternaryLabel)

                            Text("Hello World\nLorem ipsum\nKaomoji\n٩(ˊᗜˋ*)و ♡")
                                .font(.custom("IBMPlexMono-Regular", size: 13))
                                .foregroundStyle(Color.quaternaryLabel)
                        }
                        .padding(.horizontal, 4)
                        .padding(.vertical, 12)
                    }

                    TextEditor(text: $bulkContent)
                        .font(.custom("IBMPlexMono-Regular", size: 14))
                        .frame(minHeight: 200)
                        .scrollContentBackground(.hidden)
                        .opacity(bulkContent.isEmpty ? 0.25 : 1)
                }
            } header: {
                HStack {
                    Label("Snippets", systemImage: "list.bullet.rectangle")
                        .font(.custom("IBMPlexMono-SemiBold", size: 12))
                        .textCase(.uppercase)

                    Spacer()

                    Button(action: pasteBulkContentFromClipboard) {
                        Label("Paste", systemImage: "doc.on.clipboard")
                            .font(.custom("IBMPlexMono-Medium", size: 12))
                            .foregroundStyle(Color.label)
                    }
                }
            } footer: {
                BulkSnippetCounter(count: bulkSnippetsToCreateCount)
            }
            .listRowBackground(Color.tertiarySystemBackground.opacity(0.5))
        }
        .scrollContentBackground(.hidden)
    }

    // MARK: - Bulk Snippet Counter Component
    @ViewBuilder
    func BulkSnippetCounter(count: Int) -> some View {
        HStack(spacing: 8) {
            Image(systemName: count > 0 ? "checkmark.circle.fill" : "circle.dashed")
                .foregroundStyle(count > 0 ? .green : .secondary)
                .font(.system(size: 14))

            Text("\(count) snippet\(count == 1 ? "" : "s") will be created")
                .font(.custom("IBMPlexMono-Medium", size: 12))
                .foregroundStyle(count > 0 ? Color.label : .secondary)

            Spacer()

            if count > 0 {
                Text("Ready")
                    .font(.custom("IBMPlexMono-Bold", size: 10))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.green.opacity(0.2))
                    .foregroundStyle(.green)
                    .clipShape(Capsule())
            }
        }
        .padding(.top, 8)
        .animation(.easeInOut, value: count)
    }

    @ViewBuilder
    func SingleSnippetFormView() -> some View {
        Form {
            // MARK: - Snippet Type Section (Top priority)
            Section {
                SnippetTypeSelector(selection: $type, disabledItems: disabledItems)
            } header: {
                Label("Type", systemImage: "square.grid.2x2")
                    .font(.custom("IBMPlexMono-SemiBold", size: 12))
                    .textCase(.uppercase)
            }
            .listRowBackground(Color.tertiarySystemBackground.opacity(0.5))

            // MARK: - Title Section with always-visible character counter
            Section {
                TextField("Enter a title for your snippet", text: $title)
                    .disableAutocorrection(true)
                    .focused($focusedField, equals: .snippetTitle)
                    .submitLabel(.return)
                    .limitText($title, to: titleCharLimit)
                    .font(.custom("IBMPlexMono-Regular", size: 15))
            } header: {
                HStack {
                    Label("Title", systemImage: "textformat")
                        .font(.custom("IBMPlexMono-SemiBold", size: 12))
                        .textCase(.uppercase)

                    Text("*")
                        .foregroundStyle(.red)
                        .font(.custom("IBMPlexMono-Bold", size: 12))
                }
            } footer: {
                TitleCharacterCounter(title: title, limit: titleCharLimit)
            }
            .listRowBackground(Color.tertiarySystemBackground.opacity(0.5))

            // MARK: - Content Section with dynamic header
            Section {
                SnippetContentForm(
                    type: type,
                    contentValue: $content,
                    contentData: $contentFileData,
                    selectedImage: $selectedImage,
                    selectedFileMimeType: $contentFileFormatType
                )
            } header: {
                HStack {
                    Label("Content (\(type.displayText))", systemImage: type.snipTypeImage)
                        .font(.custom("IBMPlexMono-SemiBold", size: 12))
                        .textCase(.uppercase)

                    Spacer()

                    if type == .txt || type == .url {
                        Button(action: pasteContentFromClipboard) {
                            Label("Paste", systemImage: "doc.on.clipboard")
                                .font(.custom("IBMPlexMono-Medium", size: 12))
                                .foregroundStyle(Color.label)
                        }
                    }
                }
            } footer: {
                if !isKeyboardExtensionEnabled() && (type == .image || type == .file) {
                    KeyboardAccessWarning()
                        .padding(.top, 8)
                }
            }
            .listRowBackground(Color.tertiarySystemBackground.opacity(0.5))

            // MARK: - Tag Section
            Section {
                CreateOrSelectTag(snippetTag: $snippetTag)
            } header: {
                Label("Tag", systemImage: "tag")
                    .font(.custom("IBMPlexMono-SemiBold", size: 12))
                    .textCase(.uppercase)
            } footer: {
                Text("Organize your snippets for quick access")
                    .font(.custom("IBMPlexMono-Regular", size: 11))
                    .foregroundStyle(.secondary)
            }
            .listRowBackground(Color.tertiarySystemBackground.opacity(0.5))

            // MARK: - Security Section (Bottom, Collapsible)
            Section {
                DisclosureGroup(isExpanded: $isSecurityExpanded) {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle(isOn: $isSecure) {
                            HStack(spacing: 10) {
                                Image(systemName: isSecure ? "faceid" : "lock.open")
                                    .font(.system(size: 18))
                                    .foregroundStyle(isSecure ? .green : .secondary)
                                    .animation(.easeInOut, value: isSecure)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Require Authentication")
                                        .font(.custom("IBMPlexMono-Medium", size: 14))

                                    Text("FaceID / TouchID")
                                        .font(.custom("IBMPlexMono-Regular", size: 11))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .disabled(!deviceBiometrics.hasBiometricsCapability)
                        .tint(.green)

                        if !deviceBiometrics.hasBiometricsCapability {
                            Label("Biometrics not available on this device", systemImage: "exclamationmark.triangle")
                                .font(.custom("IBMPlexMono-Regular", size: 11))
                                .foregroundStyle(.orange)
                        }
                    }
                    .padding(.vertical, 4)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: isSecure ? "lock.fill" : "lock.open")
                            .font(.system(size: 16))
                            .foregroundStyle(isSecure ? .green : .secondary)

                        Text("Security")
                            .font(.custom("IBMPlexMono-Medium", size: 14))

                        if isSecure {
                            Text("ON")
                                .font(.custom("IBMPlexMono-Bold", size: 10))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.green.opacity(0.2))
                                .foregroundStyle(.green)
                                .clipShape(Capsule())
                        }
                    }
                }
                .tint(Color.label)
            }
            .listRowBackground(Color.tertiarySystemBackground.opacity(0.5))
        }
        .scrollContentBackground(.hidden)
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



    func closeForm() {
        isFormVisible = false
    }

    func pasteContentFromClipboard(){
        let clipboardContent = pasteFromClipboard()
        if !clipboardContent.isEmpty {
            content = "\(content)\(clipboardContent)"
            return
        }

        if let clipboardURL = UIPasteboard.general.url?.absoluteString {
            content = "\(content)\(clipboardURL)"
        }
    }

    func pasteBulkContentFromClipboard(){
        bulkContent = "\(bulkContent)\(pasteFromClipboard())"
    }

    private func applyInitialDraft(_ draft: SnippetFormDraft) {
        isApplyingInitialDraft = true
        formCreation = 0
        type = draft.type
        title = draft.initialTitle
        content = draft.initialContent
        snippetTag = draft.initialTag ?? SnipTag(name: "", imageTag: "tag.fill")
        contentFileData = nil
        contentFileFormatType = nil

        DispatchQueue.main.async {
            isApplyingInitialDraft = false

            guard draft.pasteClipboardOnAppear else { return }

            switch draft.type {
            case .txt, .url:
                pasteContentFromClipboard()
            case .image:
                pasteImageFromClipboard()
            case .file:
                break
            }
        }
    }

    private func pasteImageFromClipboard() {
        guard let image = UIPasteboard.general.image else { return }

        if let pngData = image.pngData() {
            contentFileData = pngData
            contentFileFormatType = "image/png"
        } else if let jpegData = image.jpegData(compressionQuality: 0.9) {
            contentFileData = jpegData
            contentFileFormatType = "image/jpeg"
        }
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
        closeForm()
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
            closeForm()
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
