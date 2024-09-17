import SwiftUI

struct Splashscreen: View {
  // State variable to control the animation
  @State private var animateText: Bool = false
  @State private var animateImage: Bool = false  // State for controlling the image animation
  @State private var progressValue: Double = 0.0

  let totalAnimationDuration: Double = 1.8

  var body: some View {
    VStack(alignment: .leading) {
        
        if let image = UIImage(named: AppIconProvider.appIcon()) {
                           Image(uiImage: image)
                               .resizable()
                               .frame(width: 72, height: 72)
                               .clipShape(
                                   RoundedRectangle(
                                       cornerRadius: 8
                                   )
                               )
                               .scaleEffect(animateImage ? 1 : 0.9)  // Start from a slightly smaller scale
                               .opacity(animateImage ? 1 : 0)  // Start with 0 opacity
                               .animation(.easeOut(duration: 0.8), value: animateImage)
                       }

      Text("Welcome to \n**SnipKey**")
        .font(.custom("IBMPlexMono-Medium", size: 32))
        .padding(.bottom, 20)
        .opacity(animateText ? 1 : 0)  // Start with 0 opacity
        .offset(y: animateText ? 0 : 20)  // Start 20 points below the final position
        .animation(.easeOut(duration: 0.8), value: animateText)  // Animate to final state
      Text(
        "**Manage** snippets of **text** and **URLs** for seamless use **across all** your **apps**."
      )
      .font(.custom("IBMPlexMono-Medium", size: 16))
      .opacity(animateText ? 1 : 0)  // Start with 0 opacity
      .offset(y: animateText ? 0 : 20)  // Start 20 points below the final position
      .animation(.easeOut(duration: 1), value: animateText)  // Animate to final state

      HStack {
        Spacer()
        ProgressView(value: progressValue, total: 1.0)
          .progressViewStyle(LinearProgressViewStyle())
        Spacer()
      }
      .padding(.top, 40)
    }
    .padding(40)
    .tint(Color.label)
    .onAppear {
      withAnimation {
        self.animateImage = true
        self.animateText = true
        // Simulate progress over the duration of the animations
        Timer.scheduledTimer(withTimeInterval: totalAnimationDuration / 100, repeats: true) {
          timer in
          // Increment the progress, ensuring it does not exceed 1.0
          self.progressValue = min(self.progressValue + 0.01, 1.0)

          // When the progress reaches or exceeds its maximum, finalize the value and invalidate the timer
          if self.progressValue >= 1 {
            self.progressValue = 1.0  // Ensure progress is exactly 1.0
            timer.invalidate()
          }
        }
      }

    }
  }
}

#Preview {
  Splashscreen()
}
