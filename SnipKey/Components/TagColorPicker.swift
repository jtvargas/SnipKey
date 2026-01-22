//
//  TagColorPicker.swift
//  SnipKey
//
//  Created by Jonathan Taveras Vargas on 1/22/26.
//

import SwiftUI

/// A grid of predefined colors for selecting tag colors
struct TagColorPicker: View {
    @Binding var selectedColorHex: String?
    
    private let columns = [GridItem(.adaptive(minimum: 44), spacing: 12)]
    
    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            // "None" option - no color
            Button {
                selectedColorHex = nil
            } label: {
                Circle()
                    .strokeBorder(Color.gray.opacity(0.5), lineWidth: 2)
                    .frame(width: 32, height: 32)
                    .overlay {
                        if selectedColorHex == nil {
                            Image(systemName: "xmark")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.gray)
                        }
                    }
            }
            .buttonStyle(.plain)
            
            // Color options from palette
            ForEach(TagColor.allCases) { tagColor in
                Button {
                    selectedColorHex = tagColor.hexValue
                } label: {
                    Circle()
                        .fill(Color(hex: tagColor.hexValue) ?? .gray)
                        .frame(width: 32, height: 32)
                        .overlay {
                            if selectedColorHex?.lowercased() == tagColor.hexValue.lowercased() {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(.white)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 8)
    }
}

#Preview {
    struct PreviewWrapper: View {
        @State private var selectedColor: String? = "#007AFF"
        
        var body: some View {
            VStack(spacing: 20) {
                Text("Selected: \(selectedColor ?? "None")")
                    .font(.headline)
                
                if let hex = selectedColor {
                    Circle()
                        .fill(Color(hex: hex) ?? .gray)
                        .frame(width: 50, height: 50)
                } else {
                    Circle()
                        .strokeBorder(Color.gray, lineWidth: 2)
                        .frame(width: 50, height: 50)
                        .overlay {
                            Text("None")
                                .font(.caption)
                        }
                }
                
                TagColorPicker(selectedColorHex: $selectedColor)
                    .padding()
            }
            .padding()
        }
    }
    
    return PreviewWrapper()
}
