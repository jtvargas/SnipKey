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
    title: "Your Data Stays Yours",
    information:
      "All your **snippets** are fully **encrypted** and **stored locally**. Your information **never leaves** your **device**.",
    image: "data_protected"
  ),
  BoardingItem(
    title: "Type Less, Express More",
    information:
      "**Create** snippets for your frequently used **text** and **URLs**. Access and **paste** them **anywhere** with our keyboard extension.",
    image: "create_snippets"
  ),
  BoardingItem(
    title: "Offline? No Problem!",
    information:
      "Your snippets are **always** at your fingertips, ready to use **offline**, **anytime**, without any internet dependency",
    image: "offline_work"
  ),
]

struct WelcomeView: View {

  var boardingItems: [BoardingItem] = welcomeItems
  @State private var viewId: Int = 0
  @AppStorage("isOnboarding") var isOnboarding: Bool?
  var skipCallback: () -> Void

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
  // MARK: - BODY

  var body: some View {
    TabView(selection: $viewId) {
      ForEach(boardingItems.indices) { index in
        BoardingCardView(boardingItem: boardingItems[index], onRightActionPress: nextItem)
          .tag(index)
      }  //: LOOP

    }  //: TAB
    .padding(.vertical, 20)
    .background(Color.customBackground)
    .tabViewStyle(PageTabViewStyle(indexDisplayMode: .always))
    .indexViewStyle(PageIndexViewStyle(backgroundDisplayMode: .never))

    HStack(
      alignment: .bottom,
      content: {
        if viewId != boardingItems.count - 1 {
          Button(action: closeWelcome) {
            Text("Skip")
              .tint(Color.black)
              .bold()
              .font(.custom("IBMPlexMono-Medium", size: 16))
              .underline()
          }
        }

        Spacer()
        Button(action: nextItem) {
          Text(viewId == boardingItems.count - 1 ? "Close" : "Next")
            .tint(Color.black)
            .bold()
            .font(.custom("IBMPlexMono-Medium", size: 16))
            .underline()
        }
      }
    )
    .padding()
    .background(Color.customBackground)

  }
}

#Preview {

  func onSkipPress() {
    print("skip")
  }

  return WelcomeView(skipCallback: onSkipPress)
}
