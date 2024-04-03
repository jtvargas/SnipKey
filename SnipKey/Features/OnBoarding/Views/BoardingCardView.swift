//
//  BoardingCardView.swift
//  SnipKey
//
//  Created by Jonathan Taveras Vargas on 3/29/24.
//

import SwiftUI

struct AdaptiveImage: View {
    @Environment(\.colorScheme) var colorScheme
    var light: Image
    var dark: Image
    
    @ViewBuilder var body: some View {
        if colorScheme == .light {
            light
                .resizable() // Apply resizable here
        } else {
            dark
                .resizable() // And here
        }
    }
}


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
                Text(.init(boardingItem.title))
                    .tint(Color.label)
                    .multilineTextAlignment(.center)
                    .font(.custom("IBMPlexMono-Medium", size: 31))
                    .shadow(color: Color(red: 0, green: 0, blue: 0, opacity: 0.15), radius: 2, x: 2, y: 2)
                
                Spacer()
                
                // Check if darkImage is provided, if so use AdaptiveImage
                if let darkImageName = boardingItem.darkImage {
                    AdaptiveImage(light: Image(boardingItem.image), dark: Image(darkImageName))
                        .scaledToFit()
                        .frame(width: 320, height: 320)
                        .scaleEffect(isAnimating ? 1.0 : 0.6)
                        .background(Color.secondarySystemBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 25))
                        .shadow(color: Color.label.opacity(0.1), radius: 8, x: 6, y: 8)
                } else {
                    Image(boardingItem.image)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 320, height: 320)
                        .scaleEffect(isAnimating ? 1.0 : 0.6)
                        .background(Color.secondarySystemBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 25))
                        .shadow(color: Color.label.opacity(0.1), radius: 8, x: 6, y: 8)
                }
                Spacer()
                
                //                use .init to support markdown formatt
                Text(.init(boardingItem.information))
                    .tint(Color.label)
                    .multilineTextAlignment(.center)
                    .font(.custom("IBMPlexMono-Medium", size: 16))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
                    .frame(maxWidth: 480)
                
                if boardingItem.action != nil {
                    Button(action: {
                        boardingItem.action?()
                    }) {
                        Text(boardingItem.actionLabel ?? "Go To Settings")
                            .tint(Color.blue)
                            .underline()
                            .font(.custom("IBMPlexMono-Medium", size: 14))
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                }
               
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
