//
//  SnippetListEmpty.swift
//  SnipKey
//
//  Created by Jonathan Taveras Vargas on 3/29/24.
//

import Combine
import SwiftUI

struct TypewriterTextView: View {
    let text: String
    @State private var displayedText = ""
    @State private var counter = 0
    @State private var timer: Timer.TimerPublisher = Timer.publish(every: 0.1, on: .main, in: .common)
    @State private var cancellable: AnyCancellable?  // Use AnyCancellable to store the subscription
    
    var body: some View {
        Text(displayedText)
            .bold()
            .font(.custom("IBMPlexMono-Medium", size: 16))
            .onAppear {
                timer = Timer.publish(every: 0.1, on: .main, in: .common)
                cancellable = timer.autoconnect().sink { _ in
                    if counter < text.count {
                        let index = text.index(text.startIndex, offsetBy: counter)
                        displayedText.append(text[index])
                        counter += 1
                    } else {
                        cancellable?.cancel()  // Cancel the subscription when done
                    }
                }
            }
    }
}

struct SnippetListEmpty: View {
    @State private var progress: CGFloat = 0
    @State private var isTilted = false
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                //        Spacer()
                Group{
                    
                    Arrow(progress: progress)
                        .size(width: geometry.size.width, height: geometry.size.height / 2)
                        .scale(0.9, anchor: .bottom)
                        .rotation(.degrees(145))
                        .padding()
                        .rotation3DEffect(.degrees(isTilted ? -10 : 10), axis: (x: 0, y: 1, z: 0))
                        .onAppear {
                            withAnimation(.easeInOut(duration: 3)) {
                                progress = 1
                            }
                        }
                    
                    TypewriterTextView(text: "No Snippets?\n Let's create one!")
                        .multilineTextAlignment(.center)
                        .italic()
                        .tint(Color.black)
                        .underline()
                        .rotation3DEffect(.degrees(isTilted ? -10 : 10), axis: (x: 0, y: 1, z: 0))
                        .onAppear {
                            withAnimation(Animation.easeInOut(duration: 1).repeatForever(autoreverses: true)) {
                                isTilted.toggle()
                            }
                        }
                        .position(x: geometry.size.width / 2, y: geometry.safeAreaInsets.top + 65)
                }
                
            }
        }
        
    }
}

#Preview {
    SnippetListEmpty()
}
