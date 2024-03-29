//
//  SnippetListEmpty.swift
//  SnipKey
//
//  Created by Jonathan Taveras Vargas on 3/29/24.
//

import Combine
import SwiftUI

struct Arrow: Shape {
  var progress: CGFloat

  var animatableData: CGFloat {
    get { progress }
    set { progress = newValue }
  }

  func path(in rect: CGRect) -> Path {
    var path = Path()
    let width = rect.size.width
    let height = rect.size.height
    path.move(to: CGPoint(x: 0.91902 * width, y: 0.00254 * height))
    path.addCurve(
      to: CGPoint(x: 0.81239 * width, y: 0.05752 * height),
      control1: CGPoint(x: 0.88236 * width, y: 0.0192 * height),
      control2: CGPoint(x: 0.84738 * width, y: 0.03752 * height))
    path.addCurve(
      to: CGPoint(x: 0.71576 * width, y: 0.11583 * height),
      control1: CGPoint(x: 0.78074 * width, y: 0.07418 * height),
      control2: CGPoint(x: 0.74242 * width, y: 0.09084 * height))
    path.addCurve(
      to: CGPoint(x: 0.73575 * width, y: 0.15081 * height),
      control1: CGPoint(x: 0.70077 * width, y: 0.12916 * height),
      control2: CGPoint(x: 0.71576 * width, y: 0.15748 * height))
    path.addCurve(
      to: CGPoint(x: 0.73742 * width, y: 0.14915 * height),
      control1: CGPoint(x: 0.73575 * width, y: 0.15081 * height),
      control2: CGPoint(x: 0.73742 * width, y: 0.15081 * height))
    path.addCurve(
      to: CGPoint(x: 0.75075 * width, y: 0.16081 * height),
      control1: CGPoint(x: 0.74242 * width, y: 0.15248 * height),
      control2: CGPoint(x: 0.74575 * width, y: 0.15581 * height))
    path.addCurve(
      to: CGPoint(x: 0.75241 * width, y: 0.16747 * height),
      control1: CGPoint(x: 0.75075 * width, y: 0.16248 * height),
      control2: CGPoint(x: 0.75241 * width, y: 0.16581 * height))
    path.addCurve(
      to: CGPoint(x: 0.76074 * width, y: 0.17747 * height),
      control1: CGPoint(x: 0.75408 * width, y: 0.17081 * height),
      control2: CGPoint(x: 0.75741 * width, y: 0.17414 * height))
    path.addCurve(
      to: CGPoint(x: 0.6108 * width, y: 0.4407 * height),
      control1: CGPoint(x: 0.71243 * width, y: 0.26744 * height),
      control2: CGPoint(x: 0.66745 * width, y: 0.3574 * height))
    path.addCurve(
      to: CGPoint(x: 0.55416 * width, y: 0.51068 * height),
      control1: CGPoint(x: 0.59414 * width, y: 0.46569 * height),
      control2: CGPoint(x: 0.57581 * width, y: 0.48902 * height))
    path.addCurve(
      to: CGPoint(x: 0.30925 * width, y: 0.34574 * height),
      control1: CGPoint(x: 0.50084 * width, y: 0.42571 * height),
      control2: CGPoint(x: 0.41421 * width, y: 0.32741 * height))
    path.addCurve(
      to: CGPoint(x: 0.31758 * width, y: 0.56899 * height),
      control1: CGPoint(x: 0.17096 * width, y: 0.37073 * height),
      control2: CGPoint(x: 0.24594 * width, y: 0.519 * height))
    path.addCurve(
      to: CGPoint(x: 0.54915 * width, y: 0.56899 * height),
      control1: CGPoint(x: 0.40254 * width, y: 0.63063 * height),
      control2: CGPoint(x: 0.47585 * width, y: 0.6273 * height))
    path.addCurve(
      to: CGPoint(x: 0.60247 * width, y: 0.75059 * height),
      control1: CGPoint(x: 0.58248 * width, y: 0.62563 * height),
      control2: CGPoint(x: 0.6058 * width, y: 0.68894 * height))
    path.addCurve(
      to: CGPoint(x: 0.35256 * width, y: 0.88553 * height),
      control1: CGPoint(x: 0.59747 * width, y: 0.89886 * height),
      control2: CGPoint(x: 0.46419 * width, y: 0.92385 * height))
    path.addCurve(
      to: CGPoint(x: 0.36422 * width, y: 0.74892 * height),
      control1: CGPoint(x: 0.36922 * width, y: 0.84221 * height),
      control2: CGPoint(x: 0.37422 * width, y: 0.79224 * height))
    path.addCurve(
      to: CGPoint(x: 0.15764 * width, y: 0.65562 * height),
      control1: CGPoint(x: 0.34756 * width, y: 0.67061 * height),
      control2: CGPoint(x: 0.22761 * width, y: 0.60064 * height))
    path.addCurve(
      to: CGPoint(x: 0.25926 * width, y: 0.87887 * height),
      control1: CGPoint(x: 0.08933 * width, y: 0.7106 * height),
      control2: CGPoint(x: 0.21761 * width, y: 0.85054 * height))
    path.addCurve(
      to: CGPoint(x: 0.29758 * width, y: 0.90219 * height),
      control1: CGPoint(x: 0.27093 * width, y: 0.8872 * height),
      control2: CGPoint(x: 0.28426 * width, y: 0.89553 * height))
    path.addCurve(
      to: CGPoint(x: 0.29425 * width, y: 0.90719 * height),
      control1: CGPoint(x: 0.29592 * width, y: 0.90386 * height),
      control2: CGPoint(x: 0.29592 * width, y: 0.90553 * height))
    path.addCurve(
      to: CGPoint(x: 0.06934 * width, y: 0.83888 * height),
      control1: CGPoint(x: 0.21761 * width, y: 1.02714 * height),
      control2: CGPoint(x: 0.11599 * width, y: 0.92385 * height))
    path.addCurve(
      to: CGPoint(x: 0.04934 * width, y: 0.85054 * height),
      control1: CGPoint(x: 0.06267 * width, y: 0.82555 * height),
      control2: CGPoint(x: 0.04435 * width, y: 0.83722 * height))
    path.addCurve(
      to: CGPoint(x: 0.27093 * width, y: 0.98216 * height),
      control1: CGPoint(x: 0.08766 * width, y: 0.93884 * height),
      control2: CGPoint(x: 0.16597 * width, y: 1.04214 * height))
    path.addCurve(
      to: CGPoint(x: 0.33257 * width, y: 0.91885 * height),
      control1: CGPoint(x: 0.29592 * width, y: 0.96717 * height),
      control2: CGPoint(x: 0.31758 * width, y: 0.94551 * height))
    path.addCurve(
      to: CGPoint(x: 0.59747 * width, y: 0.8722 * height),
      control1: CGPoint(x: 0.4242 * width, y: 0.9555 * height),
      control2: CGPoint(x: 0.53083 * width, y: 0.9555 * height))
    path.addCurve(
      to: CGPoint(x: 0.57415 * width, y: 0.54566 * height),
      control1: CGPoint(x: 0.67744 * width, y: 0.77224 * height),
      control2: CGPoint(x: 0.62746 * width, y: 0.64229 * height))
    path.addCurve(
      to: CGPoint(x: 0.57748 * width, y: 0.54233 * height),
      control1: CGPoint(x: 0.57581 * width, y: 0.54399 * height),
      control2: CGPoint(x: 0.57581 * width, y: 0.54399 * height))
    path.addCurve(
      to: CGPoint(x: 0.79073 * width, y: 0.20412 * height),
      control1: CGPoint(x: 0.67244 * width, y: 0.4507 * height),
      control2: CGPoint(x: 0.73076 * width, y: 0.32075 * height))
    path.addCurve(
      to: CGPoint(x: 0.82739 * width, y: 0.22911 * height),
      control1: CGPoint(x: 0.8024 * width, y: 0.21245 * height),
      control2: CGPoint(x: 0.81573 * width, y: 0.22078 * height))
    path.addCurve(
      to: CGPoint(x: 0.85404 * width, y: 0.22578 * height),
      control1: CGPoint(x: 0.83572 * width, y: 0.23411 * height),
      control2: CGPoint(x: 0.84738 * width, y: 0.23245 * height))
    path.addCurve(
      to: CGPoint(x: 0.95067 * width, y: 0.02586 * height),
      control1: CGPoint(x: 0.90236 * width, y: 0.16914 * height),
      control2: CGPoint(x: 0.93901 * width, y: 0.10083 * height))
    path.addCurve(
      to: CGPoint(x: 0.91902 * width, y: 0.00254 * height),
      control1: CGPoint(x: 0.95567 * width, y: 0.00754 * height),
      control2: CGPoint(x: 0.93735 * width, y: -0.00579 * height))
    path.closeSubpath()
    path.move(to: CGPoint(x: 0.48585 * width, y: 0.56565 * height))
    path.addCurve(
      to: CGPoint(x: 0.31258 * width, y: 0.51401 * height),
      control1: CGPoint(x: 0.42254 * width, y: 0.60231 * height),
      control2: CGPoint(x: 0.35923 * width, y: 0.55732 * height))
    path.addCurve(
      to: CGPoint(x: 0.36256 * width, y: 0.38406 * height),
      control1: CGPoint(x: 0.25094 * width, y: 0.45736 * height),
      control2: CGPoint(x: 0.2676 * width, y: 0.36573 * height))
    path.addCurve(
      to: CGPoint(x: 0.48085 * width, y: 0.47236 * height),
      control1: CGPoint(x: 0.41088 * width, y: 0.39405 * height),
      control2: CGPoint(x: 0.4492 * width, y: 0.43737 * height))
    path.addCurve(
      to: CGPoint(x: 0.52917 * width, y: 0.53566 * height),
      control1: CGPoint(x: 0.49751 * width, y: 0.49068 * height),
      control2: CGPoint(x: 0.51417 * width, y: 0.51234 * height))
    path.addCurve(
      to: CGPoint(x: 0.48585 * width, y: 0.56565 * height),
      control1: CGPoint(x: 0.51584 * width, y: 0.54733 * height),
      control2: CGPoint(x: 0.50084 * width, y: 0.55733 * height))
    path.closeSubpath()
    path.move(to: CGPoint(x: 0.31591 * width, y: 0.86887 * height))
    path.addCurve(
      to: CGPoint(x: 0.31591 * width, y: 0.86887 * height),
      control1: CGPoint(x: 0.31591 * width, y: 0.86887 * height),
      control2: CGPoint(x: 0.31425 * width, y: 0.86887 * height))
    path.addCurve(
      to: CGPoint(x: 0.21095 * width, y: 0.77058 * height),
      control1: CGPoint(x: 0.27093 * width, y: 0.84555 * height),
      control2: CGPoint(x: 0.23761 * width, y: 0.81223 * height))
    path.addCurve(
      to: CGPoint(x: 0.1843 * width, y: 0.7106 * height),
      control1: CGPoint(x: 0.19929 * width, y: 0.75225 * height),
      control2: CGPoint(x: 0.18929 * width, y: 0.73226 * height))
    path.addCurve(
      to: CGPoint(x: 0.28093 * width, y: 0.69394 * height),
      control1: CGPoint(x: 0.16764 * width, y: 0.65396 * height),
      control2: CGPoint(x: 0.2576 * width, y: 0.68228 * height))
    path.addCurve(
      to: CGPoint(x: 0.31591 * width, y: 0.86887 * height),
      control1: CGPoint(x: 0.34424 * width, y: 0.72893 * height),
      control2: CGPoint(x: 0.33924 * width, y: 0.8089 * height))
    path.closeSubpath()
    path.move(to: CGPoint(x: 0.83405 * width, y: 0.18247 * height))
    path.addCurve(
      to: CGPoint(x: 0.83072 * width, y: 0.1808 * height),
      control1: CGPoint(x: 0.83238 * width, y: 0.18247 * height),
      control2: CGPoint(x: 0.83238 * width, y: 0.1808 * height))
    path.addCurve(
      to: CGPoint(x: 0.82072 * width, y: 0.16747 * height),
      control1: CGPoint(x: 0.83072 * width, y: 0.1758 * height),
      control2: CGPoint(x: 0.82738 * width, y: 0.17081 * height))
    path.addCurve(
      to: CGPoint(x: 0.78573 * width, y: 0.14915 * height),
      control1: CGPoint(x: 0.80906 * width, y: 0.16248 * height),
      control2: CGPoint(x: 0.7974 * width, y: 0.15581 * height))
    path.addCurve(
      to: CGPoint(x: 0.77074 * width, y: 0.13915 * height),
      control1: CGPoint(x: 0.78073 * width, y: 0.14582 * height),
      control2: CGPoint(x: 0.77074 * width, y: 0.13582 * height))
    path.addCurve(
      to: CGPoint(x: 0.76741 * width, y: 0.13582 * height),
      control1: CGPoint(x: 0.77074 * width, y: 0.13749 * height),
      control2: CGPoint(x: 0.76907 * width, y: 0.13582 * height))
    path.addCurve(
      to: CGPoint(x: 0.82238 * width, y: 0.1025 * height),
      control1: CGPoint(x: 0.78573 * width, y: 0.12582 * height),
      control2: CGPoint(x: 0.80406 * width, y: 0.1125 * height))
    path.addCurve(
      to: CGPoint(x: 0.89569 * width, y: 0.06251 * height),
      control1: CGPoint(x: 0.84571 * width, y: 0.08917 * height),
      control2: CGPoint(x: 0.8707 * width, y: 0.07584 * height))
    path.addCurve(
      to: CGPoint(x: 0.83405 * width, y: 0.18247 * height),
      control1: CGPoint(x: 0.88403 * width, y: 0.10417 * height),
      control2: CGPoint(x: 0.86238 * width, y: 0.14582 * height))
    path.closeSubpath()
    return path
  }

  // This function uses the current progress to determine how much of the path to draw
  func trimmedPath(in rect: CGRect) -> Path {
    let fullPath = path(in: rect)
    return fullPath.trimmedPath(from: 0, to: progress)
  }
}

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
    VStack {
      Spacer()
      TypewriterTextView(text: "Start by creating some Snippets")
        .italic()
        .tint(Color.black)
        .underline()
        .rotation3DEffect(.degrees(isTilted ? -10 : 10), axis: (x: 0, y: 1, z: 0))
        .onAppear {
          withAnimation(Animation.easeInOut(duration: 1).repeatForever(autoreverses: true)) {
            isTilted.toggle()
          }
        }
      Spacer()
      Arrow(progress: progress)
        .size(width: 300, height: 560)
        .scale(1.0, anchor: .bottom)
        .rotation(.degrees(162))
        .frame(height: 560)
        .padding()
        .rotation3DEffect(.degrees(isTilted ? -10 : 10), axis: (x: 0, y: 1, z: 0))
        .onAppear {
          withAnimation(.easeInOut(duration: 3)) {
            progress = 1
          }
        }

    }
  }
}

#Preview {
  SnippetListEmpty()
}
