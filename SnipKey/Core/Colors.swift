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

}
