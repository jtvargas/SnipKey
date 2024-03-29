//
//  SnippetListItem.swift
//  SnipKey
//
//  Created by Jonathan Taveras Vargas on 3/27/24.
//

import SwiftUI

struct SnippetImage: View {
  let type: SnipType

  var body: some View {
    VStack {
      Image(systemName: type == .txt ? "character.cursor.ibeam" : "link.circle")
        .font(.headline)
    }
    .frame(width: 35, height: 35)
    .background(Color.black, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    .foregroundStyle(.white)
  }
}

struct SnippetListItem: View {
  let item: SnippetItem

  var body: some View {
    HStack {
      SnippetImage(type: item.type)

      VStack {
        Text("Item at \(item.title)")
          .bold()
          .frame(maxWidth: .infinity, alignment: .leading)
          .tint(Color.black)
          .bold()
          .font(.custom("IBMPlexMono-Medium", size: 16))

        Text("#TAG: \(item.tag)")
          .frame(maxWidth: .infinity, alignment: .leading)
          .foregroundColor(Color.customAccent)
          .font(.subheadline)
      }

    }
  }
}

#Preview {
  SnippetListItem(item: .dummy)
    .padding()
    .previewLayout(.sizeThatFits)

}
