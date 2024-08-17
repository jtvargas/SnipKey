//
//  SnippetViewDetail.swift
//  SnipKey
//
//  Created by Jonathan Taveras Vargas on 3/27/24.
//

import AlertToast
import SwiftData
import SwiftUI
import UniformTypeIdentifiers


struct SnippetContentView: View {
    let snippet: SnippetItem
    
    var body: some View {
        if snippet.type == .txt {
            ScrollView {
                Text("\(snippet.content ?? "")".toDetectedAttributedString())
                    .multilineTextAlignment(.leading)
                    .padding(.top, 8)
                    .tint(Color.label)
            }.frame(height: 180)
        }
        
        if snippet.type == .url {
            Text("\(snippet.content ?? "")".toDetectedAttributedString())
                .tint(Color.label)
        }
        
        if snippet.type == .image && snippet.file?.fileData != nil {
            if let uiImage = UIImage(data: (snippet.file?.fileData)!) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFit()
                Text("\(snippet.file?.fileFormatType ?? "")")
            }
        }
    }
}

struct SnippetViewDetail: View {
    let deviceBiometrics: DeviceBiometrics = DeviceBiometrics()
    
    @State private var showToast = false
    @State var isEditFormVisible: Bool = false
    @State private var snippet: SnippetItem = SnippetItem(
        title: "", content: "", type: SnipType.url, isSecure: false)
    @State private var showSecureAccessPrompt = false
    
    
    var body: some View {
        Group {
            if showSecureAccessPrompt {
                Section(header: Image(systemName: "lock")
                    .resizable()
                    .frame(width:88, height: 120), footer: Button{
                    toggleVisibility()
                } label: {
                    Text("Require Access")
                        .underline()
                }) {
                    
                    Text("Snippet is locked")
                }
                .padding()
                .listRowBackground(Color.tertiarySystemBackground)
            } else {
                Form {
                    Section(header: Text("title")) {
                        HStack {
                            Spacer()
                            VStack {
                                Text("\(snippet.title ?? "")")
                            }
                            Spacer()
                            
                        }
                    }
                    .frame(alignment: .center)
                    .listRowBackground(Color.tertiarySystemBackground)
                    
                    Section(header: Text("Type")) {
                        HStack {
                            Spacer()
                            VStack {
                                SnippetImage(type: snippet.type ?? SnipType.txt)
                                    .font(.system(size: 44))
                                    .frame(width: 82, height: 82)
                                    .background(
                                        Color.secondarySystemBackground,
                                        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    )
                                    .foregroundStyle(.white)
                                Text("\(snippet.type ?? SnipType.txt)")
                            }
                            Spacer()
                            
                        }
                    }
                    .listRowBackground(Color.tertiarySystemBackground)
                    
                   
                    
                    Section(
                        header: HStack {
                            Group{
                                Text("Content")
                                if snippet.type == .url {
                                    Spacer()
                                    Button(action: openURLContent) {
                                        Label("Open URL", systemImage: "arrow.up.forward.app.fill")
                                            .tint(.label)
                                            .bold()
                                            .font(.custom("IBMPlexMono-Medium", size: 14))
                                            .underline()
                                            .tint(Color.label)
                                    }
                                }
                               
                            }
                        },
                        footer: HStack {
                            Group{
                                Label("\(snippet.customTag?.name ?? "None")", systemImage: "tag.fill")
                                    .tint(.label)
                                Spacer()
                                Button(action: copyToClipboard) {
                                    Text("Copy")
                                        .bold()
                                        .font(.custom("IBMPlexMono-Medium", size: 16))
                                        .underline()
                                        .tint(Color.label)
                                }
                            }
                        }
                    ) {
                        SnippetContentViewDisplay(snippet: snippet)
                    }
                    .listRowBackground(Color.tertiarySystemBackground)
                    
                    Section(
                        footer: Group {
                                Text("Enable full keyboard access to track usage count for this snippet.")
                                    .foregroundColor(.secondary)
                                    .font(.custom("IBMPlexMono-Regular", size: 12))
                            }
                    ){
                        Text("Used Count: \(snippet.usedCount)")
                    }
                        
                   
                }
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(action: toggleEditForm) {
                            Text("Edit")
                                .bold()
                                .font(.custom("IBMPlexMono-Medium", size: 15))
                                .underline()
                                .tint(Color.label)
                        }.sheet(isPresented: $isEditFormVisible) {
                            NavigationStack {
                                SnippetForm(snippet: snippet, isFormVisible: $isEditFormVisible)
                            }
                            .presentationBackground(Color.clear)
                            
                        }
                    }
                    
                    ToolbarItem(placement: .bottomBar){
                        if snippet.updatedDate != nil {
                            Text("**Updated:** \(snippet.updatedDate?.formatted(date: .complete, time: .omitted) ?? Date.now.formatted(date: .complete, time: .omitted) )")
                                .font(.custom("IBMPlexMono-Medium", size: 12))
                        } else {
                            Text("**Created:** \(snippet.creationDate?.formatted(date: .complete, time: .omitted) ?? Date.now.formatted(date: .complete, time: .omitted) )")
                                .font(.custom("IBMPlexMono-Medium", size: 12))
                        }
                        
                        
                    }
                }
            }
        }
        .font(.custom("IBMPlexMono-Medium", size: 15))
        .tint(Color.label)
        .toast(isPresenting: $showToast) {
            AlertToast(
                displayMode: .banner(.pop), type: .systemImage("doc.on.clipboard", .label),
                title: "Copied!",
                style: .style(
                    backgroundColor: Color.tertiarySystemBackground,
                    titleFont: .custom("IBMPlexMono-Medium", size: 14)))
        }
    }
    
    init(item: SnippetItem) {
        _snippet = State(initialValue: item)
        _showSecureAccessPrompt = State(initialValue: item.isSecure)
    }
    
    func openURLContent() {
        if !snippet.content!.isEmpty  && snippet.content!.isValidURL(){
            UIApplication.shared.open(URL(string: snippet.content!.getValidURLString())!)
        }
    }
    
    func toggleVisibility(){
        deviceBiometrics.authenticate(successHandler: {
            showSecureAccessPrompt = false
        }, unSuccessHandler: { _ in
            showSecureAccessPrompt = true
        })
    }
    
    func toggleEditForm() {
        self.isEditFormVisible.toggle()
    }
    
    func copyImageToClipboard() {
        guard
            let newImage = UIImage(data: (snippet.file?.fileData)!)
        else { return }
        
        var imageData: Data?
        
        if snippet.file?.fileFormatType == "image/png"{
            imageData = newImage.pngData()
        }
        
        if snippet.file?.fileFormatType == "image/jpeg"{
            imageData = newImage.jpegData(compressionQuality: 0.5)
        }
        
        
        let clipboard = UIPasteboard.general
        clipboard.setValue(imageData!, forPasteboardType: UTType.png.identifier)
        
    }
    
    func copyToClipboard() {
        let clipboard = UIPasteboard.general
        switch snippet.type {
        case .file:
            clipboard.setValue(snippet.file?.fileData as Any, forPasteboardType: UTType.pdf.identifier)
        case .image:
            copyImageToClipboard()
        default:
            clipboard.setValue(snippet.content!, forPasteboardType: UTType.plainText.identifier)
        }
//        clipboard.setValue(snippet.content, forPasteboardType: UTType.plainText.identifier)
        showToast.toggle()
    }
}

#Preview {
    SnippetViewDetail(item: .dummy)
}
