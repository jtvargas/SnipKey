//
//  SnippetListItem.swift
//  SnipKey
//
//  Created by Jonathan Taveras Vargas on 3/27/24.
//

import SwiftUI

struct SnippetListItem: View {
    let item: SnippetItem
    var body: some View {
        HStack{
            VStack{
                Image(systemName: "character.cursor.ibeam")
                    .font(.headline)
            }
            .frame(width: 45, height: 45)
            .background(Color.black, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .foregroundStyle(.white)
            
            VStack{
                Text("Item at \(item.timestamp, format: Date.FormatStyle(date: .numeric, time: .standard))")
                    .bold()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .font(.headline)
                Text("#TAG")
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
