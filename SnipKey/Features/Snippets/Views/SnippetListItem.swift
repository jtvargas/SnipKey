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

    /// One dimmed line of content under the title so similar snippets are
    /// distinguishable before inserting. Secure content never reaches layout —
    /// the `isSecure` check must come before any `content` access.
    private var previewText: String? {
        if item.isSecure { return "••••••" }
        switch item.type ?? .txt {
        case .txt, .url:
            guard let content = item.content else { return nil }
            let head = String(content.prefix(120))
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespaces)
            return head.isEmpty ? nil : head
        case .image, .file:
            // No text content (binary blob); a type label keeps row heights
            // uniform without decoding data in grid cells.
            return (item.type ?? .txt).displayText
        }
    }

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

            // Content — title + preview + metadata with improved legibility
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title ?? "")
                    .font(.custom("IBMPlexMono-Medium", size: 14))
                    .foregroundStyle(KeyStyle.glyph(isDark: isDark))
                    .lineLimit(1)

                // Always rendered (placeholder space when empty) so every cell in
                // the grid keeps the exact same height.
                Text(previewText ?? " ")
                    .font(.custom("IBMPlexMono-Regular", size: 11))
                    .foregroundStyle(KeyStyle.tertiaryGlyph(isDark: isDark))
                    .lineLimit(1)
                    .truncationMode(.tail)

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
                    if item.customTag?.name == nil && !item.isSecure {
                        // Row would collapse to zero height with nothing to show —
                        // reserve it so untagged cells match tagged ones.
                        Text(" ")
                            .font(.custom("IBMPlexMono-Regular", size: 11))
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
