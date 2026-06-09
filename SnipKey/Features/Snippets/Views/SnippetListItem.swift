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
    /// Matches the V2 keys' light/dark signal (driven by the keyboard's
    /// `appearanceMode`, not the system color scheme). Defaults to light so the
    /// `#Preview` and any non-keyboard usage stay valid.
    var isDark: Bool = false

    var body: some View {
        let shadow = KeyStyle.keyShadow(isDark: isDark)

        return HStack(spacing: 12) {
            // Type icon — circle "well", styled like a key surface
            Image(systemName: item.type?.snipTypeImage ?? "doc.text")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(KeyStyle.secondaryGlyph(isDark: isDark))
                .frame(width: 32, height: 32)
                .background(
                    Circle()
                        .fill(KeyStyle.iconWell(isDark: isDark))
                )

            // Content — title + metadata with improved legibility
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title ?? "")
                    .font(.custom("IBMPlexMono-Medium", size: 14))
                    .foregroundStyle(KeyStyle.glyph(isDark: isDark))
                    .lineLimit(1)

                HStack(spacing: 4) {
                    if let tagName = item.customTag?.name {
                        Text("#\(tagName)")
                            .font(.custom("IBMPlexMono-Regular", size: 11))
                            .foregroundStyle(KeyStyle.secondaryGlyph(isDark: isDark))
                        TagColorIndicator(colorHex: item.customTag?.colorHex, size: 6)
                    }
                    if item.isSecure {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(KeyStyle.secondaryGlyph(isDark: isDark))
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: KeyStyle.cornerRadius, style: .continuous)
                .fill(KeyStyle.keyBackground(isDark: isDark))
                .shadow(color: shadow.color, radius: shadow.radius, x: shadow.x, y: shadow.y)
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
