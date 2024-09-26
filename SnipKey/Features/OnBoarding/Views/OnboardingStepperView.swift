//
//  OnboardingStepperView.swift
//  SnipKey
//
//  Created by Jonathan Taveras Vargas on 9/25/24.
//

import SwiftUI

struct OnboardingStepperView: View {
    // View Properties
    @State private var activePage: Page = .page1
    @State private var dragOffset: CGFloat = 0
    
    @AppStorage("showWelcomeView") var showWelcomeView: Bool = true
    
    var body: some View {
        GeometryReader {
            let size = $0.size
            
            VStack {
                Spacer()
                VStack {
                    if !activePage.media.isEmpty {
                            OverlappingMediaList(mediaItems: activePage.media, cardWidth: 120, cardHeight: 200, cardSpacing: 40)
                                .id(activePage.rawValue)
                        
                        if activePage.media.count > 1 {
                            Label("Tap to expand the image", systemImage: "rectangle.and.hand.point.up.left.fill")
                                .opacity(0.5)
                        }
                        
                    }
                
                    MorphingSymbolView(
                        symbol: activePage.rawValue,
                        config: .init(
                            font: .system(size: 45, weight: .bold),
                            frame: .init(width: 100, height: 100),
                            radius: 30,
                            foregroundColor: .white
                        )
                    )
                    if activePage == .page5 {
                        
                        
                        Button {
                            openPhoneSettings()
                        } label: {
                            Label("Open App Settings", systemImage: "gearshape.circle.fill")
                                .opacity(0.8)
                                .underline()
                                .foregroundStyle(.blue.gradient)
                        }
                    }
                    TextContent(size: size)
                }
                Spacer()
                IndicatorView()
                ContinueButton()
            }
            .frame(maxWidth: .infinity)
            .overlay(alignment: .top) {
                HeaderView()
            }
           
            
        }
        
        .background {
            Rectangle()
                .fill(.black.gradient)
                .ignoresSafeArea()
        }
        .animation(.easeInOut, value: activePage)
        .gesture(
            DragGesture()
                .onChanged { value in
                    dragOffset = value.translation.width
                }
                .onEnded { value in
                    let threshold: CGFloat = 50
                    if dragOffset > threshold {
                        withAnimation {
                            activePage = activePage.previousPage
                        }
                    } else if dragOffset < -threshold {
                        withAnimation {
                            nextPage()
                            //                            activePage = activePage.nextPage
                        }
                    }
                    dragOffset = 0
                }
        )
    }
    
    @ViewBuilder
    func HeaderView() -> some View {
        HStack {
            Button {
                activePage = activePage.previousPage
            } label: {
                Image(systemName: "chevron.left")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .contentShape(.rect)
            }
            .opacity(activePage != .page1 ? 1 : 0)
            
            Spacer()
            if activePage != .page5 {
                Button(activePage == .page5 ? "Start" : "Skip") {
                    if activePage != .page5 {
                        activePage = .page5
                    } else {
                        nextPage()
                    }
                    
                }
                .fontWeight(.semibold)
                .opacity(1)
            }
           
        }
        .foregroundStyle(.white.gradient)
        .animation(.snappy(duration: 0.35, extraBounce: 0), value: activePage)
        .padding(15)
        .sensoryFeedback(.selection, trigger: activePage)
    }
    
    @ViewBuilder
    func TextContent(size: CGSize) -> some View {
        VStack(spacing: 18) {
            HStack(alignment: .top, spacing: 0) {
                ForEach(Page.allCases, id: \.rawValue) { page in
                    Text(page.title)
                        .lineLimit(1)
                        .font(.title2)
                        .fontWeight(.semibold)
                        .kerning(1.1)
                        .frame(width: size.width)
                        .foregroundStyle(.white.gradient)
                    
                }
            }
            // Sliding Left/Right based on active page
            .offset(x: -activePage.index * size.width + dragOffset)
            .animation(.smooth(duration: 0.7, extraBounce: 0.2), value: activePage)
            
            
            HStack(alignment: .top, spacing: 0) {
                ForEach(Page.allCases, id: \.rawValue) { page in
                    Text(page.subTitle)
                        .multilineTextAlignment(.center)
                        .font(.callout)
                        .frame(width: size.width)
                        .foregroundStyle(.white.gradient)
                        
                }
                
            }
            // Sliding Left/Right based on active page
            .offset(x: -activePage.index * size.width + dragOffset)
            // Add delay with title
            .animation(.smooth(duration: 0.9, extraBounce: 0.2), value: activePage)
            
        }
        .padding(.top, 15)
        .frame(width: size.width, alignment: .leading)
    }
    
    @ViewBuilder
    func IndicatorView() -> some View {
        HStack(spacing: 6) {
            ForEach(Page.allCases, id: \.rawValue) { page in
                Capsule()
                    .fill(.white.gradient.opacity(activePage == page ? 1: 0.4))
                    .frame(width: activePage == page ? 22 : 8, height: 8)
            }
        }
        .animation(.smooth(duration: 0.5, extraBounce: 0), value: activePage)
        .padding(.bottom, 12)
    }
    
    @ViewBuilder
    func ContinueButton() -> some View {
        Button{
            nextPage()
        } label: {
            Text(activePage == .page5 ? "Start" : "Continue")
                .contentTransition(.identity)
                .foregroundStyle(.black.gradient)
                .bold()
                .padding(.vertical, 15)
                .frame(maxWidth: activePage == .page5 ? 120: 180)
                .background(.white.gradient, in: Capsule())
        }
        .pressable()
        .padding(.bottom, 15)
        .animation(.smooth(duration: 0.5, extraBounce: 0), value: activePage)
    }
    
    func nextPage() {
        switch activePage {
        case .page5:
            showWelcomeView = false
        default:
            activePage = activePage.nextPage
        }
    }

}

#Preview {
    return  OnboardingStepperView()
}
