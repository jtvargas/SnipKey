//
//  HomeSnippetList.swift
//  SnipKey
//
//  Created by Jonathan Taveras Vargas on 11/10/25.
//

import SwiftUI

struct HomeSnippetList: View {
    @Binding var editMode: EditMode
    
//    @Environment(\.editMode) var editMode
    var inEditMode: Bool {
        editMode.isEditing
    }
    
    var body: some View {
        Text("ok")
//        List(currentSnippets, id: \.self, selection: editMode.isEditing == true ? $snippetsSelection : nil) { snippetItem in
//            NavigationLink(value: snippetItem) {
//                SnippetListItem(item: snippetItem)
//            }
//            .swipeActions(edge: .leading) {
//                Button {
//                    let clipboard = UIPasteboard.general
//                    clipboard.setValue(snippetItem.content!, forPasteboardType: UTType.plainText.identifier)
//                    showToast.toggle()
//                } label: {
//                    Label("Copy", systemImage: "doc.on.doc.fill")
//                }
//                .tint(Color.quaternaryLabel)
//            }
//        }
    }
    
//    @ViewBu
}

#Preview {
    @State var mode: EditMode = .inactive
    HomeSnippetList(editMode: $mode)
}
