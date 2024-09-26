//
//  LoopVideoView.swift
//  SnipKey
//
//  Created by Jonathan Taveras Vargas on 9/25/24.
//

import SwiftUI
import AVKit
import AVFoundation

struct LoopingVideoPlayer: View {
    @State private var player: AVQueuePlayer?
    @State private var looper: AVPlayerLooper?
    
    let videoName: String
    let videoType: String
    
    init(videoName: String, videoType: String = "mov") {
        self.videoName = videoName
        self.videoType = videoType
    }
    
    var body: some View {
        VideoPlayer(player: player)
            .allowsHitTesting(false)
            .edgesIgnoringSafeArea(.all)
            .onAppear {
                if let fileURL = Bundle.main.url(forResource: videoName, withExtension: videoType) {
                    let playerItem = AVPlayerItem(url: fileURL)
                    let queuePlayer = AVQueuePlayer(playerItem: playerItem)
                    
                    // Create a new AVPlayerLooper with the queue player and player item
                    self.looper = AVPlayerLooper(player: queuePlayer, templateItem: playerItem)
                    
                    self.player = queuePlayer
                    self.player?.play()
                }
            }
            .onDisappear {
                player?.pause()
                looper?.disableLooping()
                player = nil
                looper = nil
            }
    }
}

#Preview {
    LoopingVideoPlayer(videoName: "emotion-drawing")
}
