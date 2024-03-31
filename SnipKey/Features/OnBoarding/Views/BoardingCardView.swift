//
//  BoardingCardView.swift
//  SnipKey
//
//  Created by Jonathan Taveras Vargas on 3/29/24.
//

import SwiftUI

struct BoardingCardView: View {
    // MARK: - PROPERTIES
    var boardingItem: BoardingItem
    @State private var isAnimating: Bool = false
    var onRightActionPress: () -> Void
    
    // MARK: - BODY
    
    var body: some View {
        ZStack {
            VStack() {
                Spacer()
                Text(boardingItem.title)
                    .tint(Color.label)
                    .bold()
                    .multilineTextAlignment(.center)
                    .font(.custom("IBMPlexMono-Medium", size: 31))
                    .shadow(color: Color(red: 0, green: 0, blue: 0, opacity: 0.15), radius: 2, x: 2, y: 2)
                
                Spacer()
                Image(boardingItem.image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 320, height: 320)
                    .shadow(color: Color(red: 0, green: 0, blue: 0, opacity: 0.15), radius: 8, x: 6, y: 8)
                    .scaleEffect(isAnimating ? 1.0 : 0.6)
                    .background(Color.secondarySystemBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 25))
                Spacer()
    
//                use .init to support markdown formatt
                Text(.init(boardingItem.information))
                    .tint(Color.label)
                    .multilineTextAlignment(.center)
                    .font(.custom("IBMPlexMono-Medium", size: 16))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
                    .frame(maxWidth: 480)
                Spacer()
                //                // BUTTON: START
//                StartButtonView()
            } //: VSTACK
        } //: ZSTACK
        .onAppear {
            withAnimation(.easeOut(duration: 0.5)) {
                isAnimating = true
            }
        }
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .center)
        .background(Color.systemBackground)
        .cornerRadius(20)
        .padding(.horizontal, 20)
    }
}

#Preview {
    
    func onRightActionPress(){
        print("hi")
    }
    
   return BoardingCardView(boardingItem:   BoardingItem(
        title: "Your Data Stays Yours",
        information: "All your **snippets** are fully encrypted and stored locally. Your information never leaves your device.",
        image: "data_protected"
    ), onRightActionPress: onRightActionPress)
}
