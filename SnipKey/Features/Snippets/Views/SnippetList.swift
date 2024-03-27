//
//  SnippetListItem.swift
//  SnipKey
//
//  Created by Jonathan Taveras Vargas on 3/27/24.
//

import SwiftUI

struct SnippetList: View {
    let items: [SnippetItem]
    var onDeleteHandler: (_: IndexSet) -> Void
    var body: some View {
        List {
            ForEach(items) { item in
                NavigationLink(destination: SnippetViewDetail()){
                    SnippetListItem(item: item)
                }
                .listRowBackground(Color.customSecondary)
            }
            .onDelete(perform: { indexSet in
                self.onDeleteHandler(indexSet)
            })
        }
    }
}

//#Preview {
//    SnippetList(items: [.dummy, .dummy])
//        .padding()
//        .previewLayout(.sizeThatFits)
//}
