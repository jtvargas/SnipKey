//
//  KeyboardStatusView.swift
//  SnipKey
//
//  Created by Jonathan Taveras Vargas on 3/29/24.
//

import SwiftUI

struct KeyboardStatusView: View {
    var isActive: Bool = false
    var onKeyboardStatusPress: () -> Void
    
    @State private var isAnimating = false
    @State private var lineWidth: CGFloat = 4.0
    
    let gradientSuccess = LinearGradient(
        gradient: Gradient(colors: [Color.customSuccess, Color.gray]),
        startPoint: .leading,
        endPoint: .trailing
    )
    
    let gradientError = LinearGradient(
        gradient: Gradient(colors: [Color.customError, Color.gray]),
        startPoint: .leading,
        endPoint: .trailing
    )
    
    var body: some View {
        
        Button(
            action: onKeyboardStatusPress,
            label: {
                VStack {
                    VStack(alignment: .leading) {
                        Text("Keyboard Status:")
                        HStack {
                            Image(systemName: "circle.fill")
                                .foregroundColor(isActive ? Color.customSuccess : Color.customError)
                                .symbolEffect(.pulse)
                            
                            Text(isActive ? "Ready to use" : "Not Active - Press here to activate")
                                .font(.custom("IBMPlexMono-Bold", size: 12))
                            
                            
                        }
                        
                        
                        Label("Images need Full Access enabled", systemImage: "info.square.fill")
                            .padding(.top)
                            .foregroundColor(Color.secondaryLabel)
                            .symbolEffect(.pulse)
                        
                        
                    }
                    .padding()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    GradientBorder(
                        gradient: isActive ? gradientSuccess : gradientError,
                        lineWidth: $lineWidth
                    )
                )
                .padding()
                .font(.custom("IBMPlexMono-Bold", size: 14))
                .tint(Color.label)
            })
        .onAppear {
            withAnimation(Animation.easeInOut(duration: 1).repeatForever(autoreverses: true)) {
                lineWidth = 2.0
            }
        }
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
    func handleOnKeyboardStatusPress() {
        print("Keyboard Status press")
    }
    return KeyboardStatusView(isActive: true, onKeyboardStatusPress: handleOnKeyboardStatusPress)
}
