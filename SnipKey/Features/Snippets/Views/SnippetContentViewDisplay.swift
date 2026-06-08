//
//  SnippetContentViewDisplay.swift
//  SnipKey
//
//  Created by Jonathan Taveras Vargas on 8/15/24.
//

import SwiftUI
import QuickLook

struct SnippetContentViewDisplay: View {
    let snippet: SnippetItem
    @State private var isPreviewPresented = false
    
    var body: some View {
        switch snippet.type {
        case .txt:
            textContent
        case .url:
            urlContent
        case .image:
            imageContent
        case .file:
            fileContent
        default:
            EmptyView()
        }
    }
    
    private var textContent: some View {
        ScrollView {
            Text("\(snippet.content ?? "")".toDetectedAttributedString())
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 8)
                .tint(Color.label)
        }
        // Flexible, taller viewport: short/medium snippets show far more without scrolling now
        // that the title/type header is compact; very long ones still scroll within a large area.
        .frame(minHeight: 280, maxHeight: 460)
    }
    
    private var urlContent: some View {
        Text("\(snippet.content ?? "")".toDetectedAttributedString())
            .tint(Color.label)
    }
    
    private var imageContent: some View {
        Group {
            if let fileData = snippet.file?.fileData, let uiImage = UIImage(data: fileData) {
                VStack {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFit()
                    Text("\(snippet.file?.fileFormatType ?? "")")
                }
            } else {
                Text("Image not available")
            }
        }
    }
    
    private var fileContent: some View {
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
            } label: {
                Image(systemName: "eye.fill")
                    .foregroundStyle(Color.label)
                    .font(.custom("IBMPlexMono-Medium", size: 21))
                    .frame(width: 35, height: 35)
                    .padding(8)
                    .background(Color.gray.opacity(0.2))
                    .cornerRadius(8)
            }
            .pressable()
        }
        .padding()
        .background(Color.tertiarySystemBackground.opacity(0.1))
        .cornerRadius(8)
        .sheet(isPresented: $isPreviewPresented) {
            FilePreviewSheet(fileName: "PDF Document", fileData: snippet.file?.fileData, isPresented: $isPreviewPresented)
        }
    }
}

struct FilePreviewSheet: View {
    let fileName: String
    let fileData: Data?
    @Binding var isPresented: Bool
    
    var body: some View {
        VStack {
            Label(fileName, systemImage: "doc.fill")
                .padding()
            Divider()
            if let fileData = fileData {
                FilePreviewView(fileData: fileData)
                    .padding(.horizontal, 12)
            } else {
                Text("File preview not available")
                    .padding()
            }
            Divider()
            Button {
                isPresented.toggle()
            } label: {
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


//#Preview {
//    SnippetContentViewDisplay()
//}
