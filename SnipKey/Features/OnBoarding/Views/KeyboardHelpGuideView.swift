//
//  WelcomeView.swift
//  SnipKey
//
//  Created by Jonathan Taveras Vargas on 3/29/24.
//

import SwiftUI

// MARK: - WELCOME ITEMS DATA
let keyboardGuideItems: [BoardingItem] = [
    BoardingItem(
        title: "Dive into **Settings**",
        information:
            "Head to **Settings > General > Keyboards** and find the **SnipKey Keyboard** option.",
        image: "keyboard-section-white",
        darkImage: "keyboard-section-dark"
    ),
    BoardingItem(
        title: "➕ Add Some **Magic**",
        information:
            "Tap **Add New Keyboard** to unveil all available keyboards on your device.",
        image: "add-new-section-white",
        darkImage: "add-new-section-dark"
    ),
    BoardingItem(
        title: "🔍 Find **SnipKey**",
        information:
            "Scroll through the list and select **SnipKey** to add your custom keyboard.",
        image: "select-section-white",
        darkImage: "select-section-dark"
    ),
    BoardingItem(
        title: "🎉 Ready, Set, **Type**!",
        information:
            "You're all set! Enjoy typing with **SnipKey** everywhere and access your snippets effortlessly.",
        image: "keyboard-switch-white",
        darkImage: "keyboard-switch-dark"
    ),
]


struct KeyboardHelpGuideView: View {
    var items: [BoardingItem] = keyboardGuideItems
    @State private var viewId: Int = 0
    
    @Binding var isPresented: Bool
    
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
    // MARK: - BODY
    
    var body: some View {
        TabView(selection: $viewId) {
            ForEach(items.indices) { index in
                BoardingCardView(boardingItem: items[index], onRightActionPress: nextItem)
                    .tag(index)
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
                        Text("Skip")
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
}

#Preview {
    @State var isPresentedGuide: Bool = true
    
    return KeyboardHelpGuideView(isPresented: $isPresentedGuide)
}
