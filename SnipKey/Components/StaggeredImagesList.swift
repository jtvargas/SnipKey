//
//  StaggeredImagesList.swift
//  SnipKey
//
//  Created by Jonathan Taveras Vargas on 9/25/24.
//

import SwiftUI

struct OverlappingMediaList: View {
    let mediaItems: [MediaItem]
    let cardWidth: CGFloat
    let cardHeight: CGFloat
    let cardSpacing: CGFloat
    let rotationAngle: Double
    
    @State private var appear: Bool = false
    
    init(mediaItems: [MediaItem], cardWidth: CGFloat = 200, cardHeight: CGFloat = 280, cardSpacing: CGFloat = 40, rotationAngle: Double = 5) {
        self.mediaItems = mediaItems
        self.cardWidth = cardWidth
        self.cardHeight = cardHeight
        self.cardSpacing = cardSpacing
        self.rotationAngle = rotationAngle
    }
    
    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: -cardSpacing) {
                ForEach(Array(mediaItems.enumerated()), id: \.element.id) { index, item in
                    CardView(mediaItem: item)
                        .frame(width: cardWidth, height: cardHeight)
                        .rotationEffect(self.calculateRotation(for: index))
                        .offset(y: self.calculateVerticalOffset(for: index))
                        .zIndex(Double(mediaItems.count - index))
                        .offset(y: appear ? 0 : geometry.size.height)
                        .animation(.spring(response: 0.6, dampingFraction: 0.8).delay(Double(index) * 0.1), value: appear)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .center)
        }
        .onAppear {
            appear = true
        }
    }
    
    private func calculateRotation(for index: Int) -> Angle {
        let middleIndex = Double(mediaItems.count - 1) / 2
        let relativeIndex = Double(index) - middleIndex
        return Angle(degrees: relativeIndex * rotationAngle)
    }
    
    private func calculateVerticalOffset(for index: Int) -> CGFloat {
        let middleIndex = Double(mediaItems.count - 1) / 2
        let relativeIndex = Double(index) - middleIndex
        return CGFloat(abs(relativeIndex) * 10)
    }
}

struct CardView: View {
    let mediaItem: MediaItem
    @State private var isSelected: Bool = false
    
    var body: some View {
        ZStack {
            switch mediaItem.type {
            case .image:
                Image(mediaItem.name)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            case .video(let fileExtension):
                LoopingVideoPlayer(videoName: mediaItem.name, videoType: fileExtension)
                    .frame(width: 160)
            }
        }
        .cornerRadius(20)
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
        .shadow(radius: 10)
        .scaleEffect(isSelected ? 1.1 : 1.0)
        .zIndex(isSelected ? 10 : 1)
        .rotationEffect(isSelected ? .degrees(0) : .degrees(0))
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isSelected)
        .onTapGesture {
            withAnimation {
                isSelected = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                withAnimation {
                    isSelected = false
                }
            }
        }
    }
}

#Preview {
    let mediaItems = [
           MediaItem(name: "settings-dark-keyboard", type: .image),
           MediaItem(name: "settings-dark-keyboard2", type: .image),
//           MediaItem(name: "keyboard-switch", type: .image)
       ]
    
    return OverlappingMediaList(mediaItems: mediaItems, cardWidth: 160, cardHeight: 200, cardSpacing: 40)
}
