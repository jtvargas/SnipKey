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
    
    // Add state for animation
     @State private var isAnimating: Bool = false
    


  var body: some View {

    Button(
      action: onKeyboardStatusPress,
      label: {
        VStack {
          VStack(alignment: .leading) {
            Text("Keyboard Status:")
            HStack {
              Circle()
                .fill(isActive ? Color.customSuccess : Color.customError)
                .frame(width: 12, height: 12)
                .opacity(isActive ? 1 : isAnimating ? 1 : 0.2)
                Text(isActive ? "Ready to use" :"Not Active - Press here to activate")
                .font(.custom("IBMPlexMono-Bold", size: 12))
            }
          }
          .padding()
        }
        .disabled(isActive)
        .frame(maxWidth: .infinity, alignment: .leading)
        .border(Color.secondarySystemBackground, width: 4)
        .opacity(isActive ? 1 : isAnimating ? 1 : 0.6)
        .padding()
        .font(.custom("IBMPlexMono-Bold", size: 14))
        .tint(Color.label)
        .onAppear {
            // Trigger the animation when the view appears
            withAnimation(Animation.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                isAnimating = true
            }
        }
      })

  }
}

#Preview {
  func handleOnKeyboardStatusPress() {
    print("Keyboard Status press")
  }
  return KeyboardStatusView(isActive: false, onKeyboardStatusPress: handleOnKeyboardStatusPress)
}
