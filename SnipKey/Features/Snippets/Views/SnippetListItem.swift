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
      Image(systemName: type.snipTypeImage)
          .foregroundStyle(Color.label)
          
  }
}

struct SnippetListItem: View {
  let item: SnippetItem

  var body: some View {
    HStack {
        SnippetImage(type: item.type ?? .txt)
            .frame(width: 35, height: 35)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .foregroundStyle(.white.gradient)
    
      Group {
          VStack{
              Text("\(item.title ?? "")")
                .frame(maxWidth: .infinity, alignment: .leading)
                .tint(Color.label)
                .bold()
                .font(.custom("IBMPlexMono-Medium", size: 14))

              HStack(spacing: 4) {
                  Text("#\(item.customTag?.name ?? "None")")
                      .foregroundColor(Color.secondaryLabel)
                      .font(.subheadline)
                  TagColorIndicator(colorHex: item.customTag?.colorHex, size: 8)
              }
              .frame(maxWidth: .infinity, alignment: .leading)
          }

          if item.isSecure {
              Image(systemName: "lock")
                  .foregroundStyle(Color.label.gradient)
          }
         
      }

    }
  }
}

struct SnippetListItemMinimal: View {
    let item: SnippetItem

    var body: some View {
        HStack(spacing: 12) {
            // Type icon — circle background with improved size for readability
            Image(systemName: item.type?.snipTypeImage ?? "doc.text")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color(.secondaryLabel))
                .frame(width: 32, height: 32)
                .background(
                    Circle()
                        .fill(Color(.tertiarySystemBackground))
                )

            // Content — title + metadata with improved legibility
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title ?? "")
                    .font(.custom("IBMPlexMono-Medium", size: 14))
                    .foregroundStyle(Color(.label))
                    .lineLimit(1)

                HStack(spacing: 4) {
                    if let tagName = item.customTag?.name {
                        Text("#\(tagName)")
                            .font(.custom("IBMPlexMono-Regular", size: 11))
                            .foregroundStyle(Color(.secondaryLabel))
                        TagColorIndicator(colorHex: item.customTag?.colorHex, size: 6)
                    }
                    if item.isSecure {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(Color(.secondaryLabel))
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }
}

#Preview {
//  SnippetListItem(item: .dummy)
//    .padding()
//    .previewLayout(.sizeThatFits)
    
    SnippetListItemMinimal(item: .dummy2)
        .padding()
        .previewLayout(.sizeThatFits)
    SnippetListItemMinimal(item: .dummy)
        .padding()
        .previewLayout(.sizeThatFits)

}
