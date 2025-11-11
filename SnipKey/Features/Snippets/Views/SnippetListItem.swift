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

                Text("#\(item.customTag?.name ?? "None")")
                .frame(maxWidth: .infinity, alignment: .leading)
                .foregroundColor(Color.secondaryLabel)
                .font(.subheadline)
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
        HStack(spacing: 10) {
            // Compact icon
            Image(systemName: item.type?.snipTypeImage ?? "doc.text")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.primary)
                .frame(width: 28, height: 28)
                .background {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay {
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color.white.opacity(0.12),
                                            Color.white.opacity(0.04)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
                        }
                }
            
            // Content
            VStack(alignment: .leading, spacing: 2) {
                HStack() {
                    Text(item.title ?? "")
                        .font(.custom("IBMPlexMono-Medium", size: 14))
                            .foregroundStyle(Color.primary)
                           .lineLimit(2)
                           .multilineTextAlignment(.leading)
                           .frame(width: 110, alignment: .leading)

                    
                    if item.isSecure {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 6))
                            .foregroundStyle(Color.primary.opacity(0.6))
                    }
                }
                
//                if item.customTag?.name != nil {
                    Text("#\(item.customTag?.name ?? "None")")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(Color.primary.opacity(0.5))
                        .lineLimit(1)
//                }
             
            }
            
            
        }
        .fixedSize(horizontal: true, vertical: false)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.08),
                                    Color.white.opacity(0.02)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
                }
        }
        .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
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
