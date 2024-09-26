//
//  WelcomeView.swift
//  SnipKey
//
//  Created by Jonathan Taveras Vargas on 3/29/24.
//

import SwiftUI

func openPhoneSettings() {
  guard let url = URL(string: UIApplication.openSettingsURLString) else {
    return
  }

  if UIApplication.shared.canOpenURL(url) {
    UIApplication.shared.open(url, options: [:], completionHandler: nil)
  }
}

// MARK: - WELCOME ITEMS DATA
let keyboardGuideItems: [BoardingItem] = [
  BoardingItem(
    title: "Dive into **Settings**",
    information:
      "Head to **App Settings > Keyboards**",
    image: "settings-white-keyboard",
    darkImage: "settings-dark-keyboard",
    action: { openPhoneSettings() },
    actionLabel: "Go to Settings"
  ),
  BoardingItem(
    title: "➕ Add Some **Magic**",
    information:
      "To use basic features (text/URLs), enable the **'Shortcuts'** toggle.\n\nFor advanced features (images/PDFs/quick creation), enable **'Full Access'**.\n\n**Note**: **Full Access** and **Shortcuts** must be enabled to manipulate data between the keyboard extension and the app per Apple policies.",
    image: "settings-white-keyboard2",
    darkImage: "settings-dark-keyboard2"
  ),
  BoardingItem(
    title: "🎉 Ready, Set, **Type**!",
    information:
      "You're all set! Enjoy using **SnipKey** to access your snippets easily.\n\nIf you encounter setup issues, **close** the app, **open a text editor**, **switch** to the SnipKey keyboard, then **reopen** the app. If problems persist, please contact us via the settings screen.",
    image: "keyboard-switch",
    darkImage: "keyboard-switch"
  ),
]

struct KeyboardHelpGuideView: View {
  var items: [BoardingItem] = keyboardGuideItems
  @State private var viewId: Int = 0

  @Binding var isPresented: Bool

  // MARK: - BODY
  var body: some View {
    TabView(selection: $viewId) {
    
      ForEach(items.indices) { index in
          ScrollView{
              BoardingCardView(boardingItem: items[index], onRightActionPress: nextItem)
                .tag(index)
          }
        
      }  //: LOOP

    }  //: TAB
    .padding(.vertical, 20)
    .background(Color.systemBackground)
    .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))

    HStack(
      alignment: .bottom,
      content: {
        if viewId != items.count - 1 {
          Button(action: closeWelcome) {
            Text("Close")
              .tint(Color.label)
              .bold()
              .font(.custom("IBMPlexMono-Medium", size: 16))
              .underline()
          }
        }

        Spacer()
        Button(action: nextItem) {
          Text(viewId == items.count - 1 ? "Close" : "Next")
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
      if tempViewId > items.count - 1 {
        closeWelcome()
      } else {
        viewId = tempViewId
      }
    }

  }

  func closeWelcome() {
    print("Skip")
    isPresented = false
    viewId = 0
  }
}

#Preview {
  @State var isPresentedGuide: Bool = true

  return KeyboardHelpGuideView(isPresented: $isPresentedGuide)
}
