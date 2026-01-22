//
//  TagColorIndicator.swift
//  SnipKey
//
//  Created by Jonathan Taveras Vargas on 1/22/26.
//

import SwiftUI

/// A small colored circle indicator for displaying tag colors
struct TagColorIndicator: View {
    let colorHex: String?
    var size: CGFloat = 8
    
    var body: some View {
        if let hex = colorHex, let color = Color(hex: hex) {
            Circle()
                .fill(color)
                .frame(width: size, height: size)
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        // With color
        HStack {
            TagColorIndicator(colorHex: "#FF3B30")
            Text("Red Tag")
        }
        
        HStack {
            TagColorIndicator(colorHex: "#007AFF")
            Text("Blue Tag")
        }
        
        HStack {
            TagColorIndicator(colorHex: "#34C759", size: 12)
            Text("Green Tag (larger)")
        }
        
        // Without color (nil)
        HStack {
            TagColorIndicator(colorHex: nil)
            Text("No Color Tag")
        }
    }
    .padding()
}
