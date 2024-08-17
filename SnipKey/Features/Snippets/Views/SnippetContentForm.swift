//
//  SnippetContentForm.swift
//  SnipKey
//
//  Created by Jonathan Taveras Vargas on 8/15/24.
//

import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import QuickLook
import PDFKit

struct SnippetContentForm: View {
    let type: SnipType
    
    @Binding var contentValue: String
    @Binding var contentData: Data?
    @Binding var selectedImage: PhotosPickerItem?
    @Binding var selectedFileMimeType: String?
    
    var body: some View {
        switch type {
        case .url:
            URLContentView(contentValue: $contentValue)
        case .txt:
            TextContentView(contentValue: $contentValue)
        case .image:
            ImageContentView(
                selectedImage: $selectedImage,
                selectedImageData: $contentData,
                selectedImageMimeType: $selectedFileMimeType
            )
        case .file:
            FileContentView(contentData: $contentData, selectedFileMimeType: $selectedFileMimeType)
        default:
            EmptyView()
        }
    }
}

// MARK: - URL Content View
private struct URLContentView: View {
    @Binding var contentValue: String
    
    var body: some View {
        VStack(alignment: .leading) {
            URLTextField(contentValue: $contentValue)
            
            if contentValue.isValidURL() {
                OpenURLButton(url: contentValue)
            }
        }
    }
}

private struct URLTextField: View {
    @Binding var contentValue: String
    
    var body: some View {
        TextField("https://yoursite.com", text: $contentValue, axis: .vertical)
            .disableAutocorrection(true)
            .keyboardType(.URL)
            .textContentType(.URL)
            .textInputAutocapitalization(.never)
            .submitLabel(.return)
            .tint(Color.label)
    }
}

private struct OpenURLButton: View {
    let url: String
    
    var body: some View {
        Button(action: openURL) {
            Text("Open URL")
                .tint(Color.blue)
        }
    }
    
    private func openURL() {
        if !url.isEmpty && url.isValidURL() {
            UIApplication.shared.open(URL(string: url.getValidURLString())!)
        }
    }
}

// MARK: - Text Content View
private struct TextContentView: View {
    @Binding var contentValue: String
    
    var body: some View {
        TextField("Content", text: $contentValue, axis: .vertical)
            .disableAutocorrection(true)
            .textInputAutocapitalization(.never)
            .lineLimit(5...10)
            .submitLabel(.return)
    }
}

// MARK: - Image Content View
private struct ImageContentView: View {
    @Binding var selectedImage: PhotosPickerItem?
    @Binding var selectedImageData: Data?
    @Binding var selectedImageMimeType: String?
    
    var body: some View {
        VStack {
            ImagePicker(
                selectedImage: $selectedImage,
                selectedImageData: $selectedImageData
            )
            
            if !isKeyboardExtensionEnabled() {
                KeyboardAccessWarning()
            }
        }
        .task(id: selectedImage) {
            await loadSelectedImage()
        }
    }
    
    private func loadSelectedImage() async {
        if let data = try? await selectedImage?.loadTransferable(type: Data.self) {
            selectedImageData = data
            selectedImageMimeType = selectedImage?.supportedContentTypes.first?.preferredMIMEType
        }
    }
}

private struct ImagePicker: View {
    @Binding var selectedImage: PhotosPickerItem?
    @Binding var selectedImageData: Data?
    
    var body: some View {
        PhotosPicker(
            selection: $selectedImage,
            matching: .images,
            preferredItemEncoding: .compatible,
            photoLibrary: .shared()
        ) {
            ImagePickerContent(selectedImageData: selectedImageData)
        }
        .overlay(alignment: .topTrailing) {
            if selectedImageData != nil {
                RemoveImageButton(action: clearSelectedImage)
            }
        }
    }
    
    private func clearSelectedImage() {
        selectedImage = nil
        selectedImageData = nil
    }
}

private struct ImagePickerContent: View {
    let selectedImageData: Data?
    
    var body: some View {
        Group {
            if let selectedImageData, let uiImage = UIImage(data: selectedImageData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFit()
            } else {
                Label {
                    Text("Select Photo")
                        .font(.system(size: 16, weight: .light, design: .rounded))
                        .multilineTextAlignment(.center)
                        .tint(.label)
                        .underline()
                } icon: {
                    Image(systemName: "photo.badge.plus")
                        .foregroundColor(.label)
                }
            }
        }
    }
}

private struct RemoveImageButton: View {
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Image(systemName: "x.circle.fill")
                .padding(8)
                .font(.custom("IBMPlexMono-Medium", size: 14))
                .foregroundStyle(.white)
                .background(.red)
                .cornerRadius(8)
        }
        .padding()
    }
}

// MARK: - File Content View (PDF)
private struct FileContentView: View {
    @Binding var contentData: Data?
    @Binding var selectedFileMimeType: String?
    @State private var isFilePickerPresented = false
    @State private var showFilePicker = false
    
    var body: some View {
        if let selectedDocument = contentData {
            SelectedFileView(fileData: selectedDocument, removeAction: clearSelectedFile)
        } else {
            SelectFileButton(action: { showFilePicker = true })
                .fileImporter(
                    isPresented: $showFilePicker,
                    allowedContentTypes: [UTType.pdf],
                    allowsMultipleSelection: false
                ) { result in
                    switch result {
                    case .success(let files):
                        if let file = files.first, file.startAccessingSecurityScopedResource() {
                            defer { file.stopAccessingSecurityScopedResource() }
                            if let data = try? Data(contentsOf: file) {
                                contentData = data
                                selectedFileMimeType = "application/pdf"
                            }
                        }
                    case .failure(let error):
                        print("Error selecting file: \(error.localizedDescription)")
                    }
                }
        }
    }
    
    
    private func clearSelectedFile() {
        contentData = nil
        selectedFileMimeType = nil
    }
}


private struct SelectedFileView: View {
    let fileData: Data?
    let removeAction: () -> Void
    @State private var isPreviewPresented = false
    
    var body: some View {
        VStack {
            HStack {
                HStack {
                    Image(systemName: "doc.fill")
                        .foregroundStyle(Color.label)
                    Text("PDF Document")
                        .font(.custom("IBMPlexMono-Medium", size: 16))
                        .lineLimit(1)
                        .foregroundStyle(.primary)
                   
                }
                Spacer()
                
                Button {
                    isPreviewPresented.toggle()
                }label: {
                    Image(systemName: "eye.fill")
                        .foregroundStyle( Color.label)
                        .font(.custom("IBMPlexMono-Medium", size: 21))
                        .frame(width: 35, height: 35)
                        .padding(8)
                        .background(Color.gray.opacity(0.2))
                        .cornerRadius(8)
                }
                .pressable()
                
                Divider()
                
                Button {
                    removeAction()
                }label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.red.gradient)
                        .font(.custom("IBMPlexMono-Medium", size: 21))
                        .frame(width: 35, height: 35)
                        .padding(8)
                        .background(Color.gray.opacity(0.2))
                        .cornerRadius(8)

                }
                .pressable()
               
                
            }
            
            Label("Some apps don't support sending documents via keyboard.", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
        }
        .padding()
        .background(Color.tertiarySystemBackground.opacity(0.1))
        .cornerRadius(8)
        .sheet(isPresented: $isPreviewPresented) {
            VStack {
                Label("PDF Document", systemImage: "doc.fill")
                    .padding()
                Divider()
                FilePreviewView(fileData: fileData!)
                    .padding(.horizontal, 12)
                Divider()
                Button {
                    isPreviewPresented.toggle()
                }label: {
                    Label("Close", systemImage: "xmark.circle.fill")
                        .padding(8)
                        .background(Color.gray.opacity(0.2))
                        .cornerRadius(8)
                }
                .pressable()
                .padding(.bottom, 8)
               
            }
            
        }
    }
}

struct FilePreviewView: UIViewRepresentable {
    let fileData: Data
    
    func makeUIView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        return pdfView
    }
    
    func updateUIView(_ uiView: PDFView, context: Context) {
        if let pdfDocument = PDFDocument(data: fileData) {
            uiView.document = pdfDocument
        }
    }
}

private struct SelectFileButton: View {
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
                Label {
                    Text("Select PDF")
                        .font(.system(size: 16, weight: .light, design: .rounded))
                        .multilineTextAlignment(.center)
                        .tint(.label)
                        .underline()
                } icon: {
                    Image(systemName: "doc.badge.plus")
                        .foregroundColor(.label)
                }
        }
    }
}

private struct KeyboardAccessWarning: View {
    var body: some View {
        Label {
            VStack {
                Text("To use image snippets, please enable full access for the keyboard in your device's keyboard settings.")
                    .foregroundColor(.yellow)
                Button(action: openSettings) {
                    Text("Go to Settings")
                        .underline()
                        .padding(.top, 4)
                }
            }
        } icon: {
            Image(systemName: "info")
                .foregroundColor(.yellow)
        }
    }
    
    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString),
           UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
        }
    }
}


