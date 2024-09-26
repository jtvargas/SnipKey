//
//  KeyboardStatusView.swift
//  SnipKey
//
//  Created by Jonathan Taveras Vargas on 3/29/24.
//

import SwiftUI
import Pow

struct KeyboardStatusView: View {
    var isShortcutsActive: Bool  = false
    var onKeyboardStatusPress: () -> Void
    
    @State private var isAnimating = false
    @State private var lineWidth: CGFloat = 4.0
    
    let gradientSuccess = LinearGradient(
        gradient: Gradient(colors: [Color.customSuccess, Color.gray]),
        startPoint: .leading,
        endPoint: .trailing
    )
    
    let gradientShortcutsOnlyEnabled = LinearGradient(
        gradient: Gradient(colors: [Color.orange, Color.gray]),
        startPoint: .leading,
        endPoint: .trailing
    )
    
    let gradientError = LinearGradient(
        gradient: Gradient(colors: [Color.customError, Color.gray]),
        startPoint: .leading,
        endPoint: .trailing
    )
    
    var borderBoxColorGradient: LinearGradient {
        if isShortcutsActive {
            return gradientSuccess
        }
        
        return gradientError
    }
    
    var body: some View {
        
        let shortcutsBoxColor = isShortcutsActive ? Color.customSuccess : Color.customError
        
        Button {
            onKeyboardStatusPress()
        }label: {
            VStack {
                VStack(alignment: .leading) {
                    Text("Keyboard Status:")
                    HStack {
//                            Image(systemName: "circle.fill")
//                                .foregroundColor(colorBox)
//                                .symbolEffect(.pulse)
                        VStack(alignment: .leading, spacing: 6) {
//                                Text(isActive ? "Ready to use" : "Keyboard Extension setup needed. Tap here")
//
                            
//                            Label(isActive ? "Ready to use" : "Keyboard Extension setup needed. Tap here", systemImage: "circle.fill")
//                                .foregroundColor(colorBox)
//                                .symbolEffect(.pulse)
//                                .font(.custom("IBMPlexMono-Bold", size: 12))
                            
                            Label("Shortcuts Enabled", systemImage: isShortcutsActive ? "checkmark.circle.fill" : "x.circle.fill")
                                .padding(.top, 2)
                                .foregroundColor(shortcutsBoxColor)
                                .font(.custom("IBMPlexMono-Bold", size: 12))
                            
//                            Label("Full Access Enabled", systemImage: isFullAccessActive ? "checkmark.circle.fill" : "x.circle.fill")
//                                .foregroundColor(fullAccessBoxColor)
//                                .font(.custom("IBMPlexMono-Bold", size: 12))
                        }
                       

                    }
                        Label("Enable Full Access for Images & Files", systemImage: "info.square.fill")
                            .padding(.top, 4)
                            .foregroundColor(Color.secondaryLabel)
                            .symbolEffect(.pulse)
                   
                    
                    
                }
                .padding()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                GradientBorder(
                    gradient: borderBoxColorGradient,
                    lineWidth: $lineWidth
                )
            )
            .font(.custom("IBMPlexMono-Bold", size: 14))
            .tint(Color.label)
        }
        .conditionalEffect(
            .repeat(
                
                .glow(color: shortcutsBoxColor, radius: 6),
                
                every: 1.5
                
            ),
            
            condition: true
            
        )
    }
}

struct GradientBorder: View {
    var gradient: LinearGradient
    @Binding var lineWidth: CGFloat
    
    var body: some View {
        GeometryReader { geometry in
            RoundedRectangle(cornerRadius: 5)
                .stroke(gradient, lineWidth: lineWidth)
        }
    }
}


#Preview {
    KeyboardStatusView(
        isShortcutsActive: true,
        onKeyboardStatusPress: { }
    )
}
