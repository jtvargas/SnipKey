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

  func test() {
    print("hello world")
  }

  var body: some View {
    List {
      ForEach(items, id: \.self.id) { item in
        NavigationLink(destination: SnippetViewDetail()) {
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
