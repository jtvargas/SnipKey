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
              Text("Not Active - Press here to activate")
                .font(.custom("IBMPlexMono-Bold", size: 12))
            }
          }
          .padding()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .border(Color.customSecondary)
        .padding()
        .font(.custom("IBMPlexMono-Bold", size: 14))
        .tint(Color.black)
      })

  }
}

#Preview {
  func handleOnKeyboardStatusPress() {
    print("Keyboard Status press")
  }
  return KeyboardStatusView(isActive: false, onKeyboardStatusPress: handleOnKeyboardStatusPress)
}
