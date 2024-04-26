//
//  SnippetFilesView.swift
//  SnipKey
//
//  Created by Jonathan Taveras Vargas on 4/26/24.
//

import Foundation
import SwiftUI
import SwiftUIMasonry
import SwiftData
import AlertToast

struct SnippetFilesView: View {
    @Query(sort: \SnippetItem.creationDate, order: .reverse, animation: .bouncy) private var snippets:
    [SnippetItem]
    @Query(sort: \SnipTag.name) private var tags: [SnipTag]
    @Query(sort: \SnippetFile.id, order: .reverse, animation: .bouncy) private var files:
    [SnippetFile]
    
    @State private var showToast = false
    
    var body: some View {
        VStack(alignment: .leading, content: {
            Label("Images", systemImage: "rectangle.grid.3x2.fill")
        })
        .padding(.top)
        
        
        
        ScrollView(.vertical) {
            Masonry(.vertical, lines: 3, spacing: 6) {
                ForEach(0..<files.count, id: \.self) { index in
                    VStack {
                        HStack {
                            if let snippetItem = files[index].snippet?.first ,let imageData = files[index].fileData , let uiImage = UIImage(data: imageData) {
                                
                                Button {
                                    if let fileCopied = copyImageToClipboard(snippet: snippetItem) {
                                        showToast.toggle()
                                    }
                                } label: {
                                    Image(uiImage: uiImage)
                                        .resizable()
                                        .frame(width: 110, height:getHeight(index: index))
                                        .scaledToFit()
                                        .background(Color.blue)
                                        .cornerRadius(10)
                                        .overlay(
                                            Text("\(snippetItem.title)")
                                                .lineLimit(1) // Limit text to a single line
                                                .truncationMode(.tail)
                                                .padding(6)
                                                .background(Color.black.opacity(0.5))
                                                .foregroundColor(.white)
                                                .cornerRadius(5),
                                            alignment: .bottom
                                        )
                                        .overlay(      Image(systemName: snippetItem.customTag!.imageTag)
                                            .padding(6)
                                            .background(Color.black.opacity(0.5))
                                            .foregroundColor(.white)
                                            .cornerRadius(10),
                                                       alignment: .topLeading)
                                }
                                
                                
                                
                                
                            }
                        }
                    }
                }
            }
        }
        .padding()
        .parallax(amount: 28)
        .toast(isPresenting: $showToast) {
            AlertToast(
                displayMode: .banner(
                    .pop
                ),
                type: .systemImage(
                    "doc.on.clipboard",
                    .label
                ),
                title: "Image copied to your clipboard.\nPaste to use it!",
                style: .style(
                    backgroundColor: Color.tertiarySystemBackground,
                    titleFont: .custom(
                        "IBMPlexMono-Medium",
                        size: 14
                    )
                )
            )
        }
        
    }
    
    func getHeight(index: Int) -> CGFloat {
        
        
        if index % 2 == 0 {
            return CGFloat(140)
        }
        
        if index % 3 == 0 {
            return CGFloat(170)
        }
        
        if index % 5 == 0 {
            return CGFloat(190)
        }
        
        return CGFloat(180)
    }
}

#Preview {
    let container = SnipKeyDataManager().makeSharedContainer()
    
    return SnippetFilesView()
        .modelContainer(container)
}
