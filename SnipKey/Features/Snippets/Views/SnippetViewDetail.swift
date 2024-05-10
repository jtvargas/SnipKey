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
                Text("\(snippet.content)")
                    .multilineTextAlignment(.leading)
                    .padding(.top, 8)
                    .tint(Color.label)
            }.frame(height: 180)
        }
        
        if snippet.type == .url {
            Text("\(snippet.content)")
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
                    Section(header: Text("Type")) {
                        HStack {
                            Spacer()
                            VStack {
                                SnippetImage(type: snippet.type)
                                    .font(.system(size: 44))
                                    .frame(width: 82, height: 82)
                                    .background(
                                        Color.secondarySystemBackground,
                                        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    )
                                    .foregroundStyle(.white)
                                Text("\(snippet.type)")
                            }
                            Spacer()
                            
                        }
                    }
                    .listRowBackground(Color.tertiarySystemBackground)
                    
                    Section(header: Text("title")) {
                        HStack {
                            Spacer()
                            VStack {
                                Text("\(snippet.title)")
                            }
                            Spacer()
                            
                        }
                    }
                    .frame(alignment: .center)
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
                        SnippetContentView(snippet: snippet)
                    }
                    .listRowBackground(Color.tertiarySystemBackground)
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
                            Text("**Updated:** \(snippet.updatedDate?.formatted(date: .complete, time: .omitted) ?? "" )")
                                .font(.custom("IBMPlexMono-Medium", size: 12))
                        } else {
                            Text("**Created:** \(snippet.creationDate.formatted(date: .complete, time: .omitted) )")
                                .font(.custom("IBMPlexMono-Medium", size: 12))
                        }
                        
                        
                    }
                }
            }
        }
        .navigationTitle("\(snippet.title)")
        .font(.custom("IBMPlexMono-Medium", size: 15))
        .bold()
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
        if !snippet.content.isEmpty  && snippet.content.isValidURL(){
            UIApplication.shared.open(URL(string: snippet.content.getValidURLString())!)
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
    
    func copyToClipboard() {
        let clipboard = UIPasteboard.general
        clipboard.setValue(snippet.content, forPasteboardType: UTType.plainText.identifier)
        showToast.toggle()
    }
}

#Preview {
    SnippetViewDetail(item: .dummy)
}
