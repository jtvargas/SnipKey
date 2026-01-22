//
//  Colors.swift
//  SnipKey
//
//  Created by Jonathan Taveras Vargas on 3/27/24.
//

import Foundation
import SwiftUI

extension Color {
    public static var customBackground: Color {
        return Color(UIColor(red: 255/255, green: 255/255, blue: 255/255, alpha: 1.0))
    }
    public static var customSecondary: Color {
        return Color(UIColor(red: 231/255, green: 231/255, blue: 231/255, alpha: 1.0))
    }
    public static var customAccent: Color {
        return Color(UIColor(red: 96/255, green: 125/255, blue: 139/255, alpha: 1.0))
    }
    public static var customError: Color {
        return Color(UIColor(red: 255/255, green: 94/255, blue: 87/255, alpha: 1.0))
    }
    public static var customSuccess: Color {
        return Color(UIColor(red: 38/255, green: 222/255, blue:129/255, alpha: 1.0))
    }

    static let lightText = Color(UIColor.lightText)
    static let darkText = Color(UIColor.darkText)
    
    static let label = Color(UIColor.label)
    static let secondaryLabel = Color(UIColor.secondaryLabel)
    static let tertiaryLabel = Color(UIColor.tertiaryLabel)
    static let quaternaryLabel = Color(UIColor.quaternaryLabel)
    
    static let systemBackground = Color(UIColor.systemBackground)
    static let secondarySystemBackground = Color(UIColor.secondarySystemBackground)
    static let tertiarySystemBackground = Color(UIColor.tertiarySystemBackground)
    
    // MARK: - Hex Color Support
    
    /// Initialize a Color from a hex string (e.g., "#FF3B30" or "FF3B30")
    init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")
        
        guard hexSanitized.count == 6 else { return nil }
        
        var rgb: UInt64 = 0
        guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else { return nil }
        
        let red = Double((rgb & 0xFF0000) >> 16) / 255.0
        let green = Double((rgb & 0x00FF00) >> 8) / 255.0
        let blue = Double(rgb & 0x0000FF) / 255.0
        
        self.init(red: red, green: green, blue: blue)
    }
    
    /// Convert Color to hex string (returns nil if conversion fails)
    func toHex() -> String? {
        guard let components = UIColor(self).cgColor.components else { return nil }
        
        let red: CGFloat
        let green: CGFloat
        let blue: CGFloat
        
        if components.count >= 3 {
            red = components[0]
            green = components[1]
            blue = components[2]
        } else if components.count >= 1 {
            // Grayscale
            red = components[0]
            green = components[0]
            blue = components[0]
        } else {
            return nil
        }
        
        return String(
            format: "#%02X%02X%02X",
            Int(red * 255),
            Int(green * 255),
            Int(blue * 255)
        )
    }
}
