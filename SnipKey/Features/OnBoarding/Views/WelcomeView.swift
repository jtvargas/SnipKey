//
//  WelcomeView.swift
//  SnipKey
//
//  Created by Jonathan Taveras Vargas on 3/29/24.
//

import SwiftUI

// MARK: - WELCOME ITEMS DATA

let welcomeItems: [BoardingItem] = [
  BoardingItem(
    title: "Welcome to\n**SnipKey!**",
    information:
      "Unlock the power of **quick**, **organized snippets**. **Save time** and boost productivity with **easy shortcuts** **fr**om **your keyboard.**",
    image: "welcome-snipkey2"
  ),
  BoardingItem(
    title: "Your Data Stays Secure",
    information:
        "All your **snippets** are securely **encrypted** and **synchronized** across devices via iCloud. Your information is safe and accessible **wherever you go**.",
    image: "data_protected"
  ),
  BoardingItem(
    title: "Type Less, Express More",
    information:
      "**Create** snippets for your frequently used **text** and **URLs**. Access and **paste** them **anywhere** with our keyboard extension.",
    image: "create_snippets"
  ),
  BoardingItem(
    title: "Before start✋\n\nLet's Set Up Your Keyboard",
    information:
      "Enable and start using the keyboard extension in just a few steps:\n\n1. Go to **Settings** > **General** > **Keyboard** > **Keyboards**.\n\n2. Tap **Add New Keyboard** and select **SnipKey** from the list.\n\n3. Enable **Allow Full Access** to utilize all features securely (Images, Fast snippet creation...).",
    image: nil,
    action: { openPhoneSettings() },
    actionLabel: "Go to Settings"
  ),
]

struct WelcomeView: View {

  var boardingItems: [BoardingItem] = welcomeItems
  @State private var viewId: Int = 0
  @AppStorage("isOnboarding") var isOnboarding: Bool?
  var skipCallback: () -> Void
  // MARK: - BODY
    
    

  var body: some View {
      
    TabView(selection: $viewId) {
        ForEach(boardingItems.indices) { index in
            BoardingCardView(boardingItem: boardingItems[index], onRightActionPress: nextItem)
                .tag(index)

      }  //: LOOP

    }  //: TAB
    .padding(.vertical, 20)
    .background(Color.systemBackground)
    .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))

    HStack(
      alignment: .bottom,
      content: {
        if viewId != boardingItems.count - 1 {
          Button(action: closeWelcome) {
            Text("Skip")
              .tint(Color.label)
              .bold()
              .font(.custom("IBMPlexMono-Medium", size: 16))
              .underline()
          }
        }

        Spacer()
        Button(action: nextItem) {
          Text(viewId == boardingItems.count - 1 ? "Close" : "Next")
            .tint(Color.label)
            .bold()
            .font(.custom("IBMPlexMono-Medium", size: 16))
            .underline()
        }
      }
    )
    .padding()
    .background(Color.systemBackground)

  }

  func nextItem() {
    let tempViewId = viewId + 1
    withAnimation {
      if tempViewId > boardingItems.count - 1 {
        closeWelcome()
      } else {
        viewId = tempViewId
      }
    }

  }

  func closeWelcome() {
    print("Skip")
    isOnboarding = false
    skipCallback()
    viewId = 0
  }
}

#Preview {

  func onSkipPress() {
    print("skip")
  }

  return WelcomeView(skipCallback: onSkipPress)
}
