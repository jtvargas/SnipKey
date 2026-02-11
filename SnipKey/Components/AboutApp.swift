//
//  AboutApp.swift
//  SnipKey
//
//  Created by Jonathan Taveras Vargas on 9/26/24.
//

import SwiftUI

struct AboutView: View {
    @State private var circlesAppeared = false
    
    let appInfo: AppInfo
    let otherApps: [AppLink]
    let aboutSections: [String]
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headerSection
                appDescriptionSection
                otherAppsSection
            }
            .padding()
        }
        .background(Color(.systemBackground))
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8, blendDuration: 0.8)) {
                circlesAppeared = true
            }
        }
    }
    
    private var headerSection: some View {
        HStack(spacing: -20) {
            ForEach(appInfo.images.indices, id: \.self) { index in
                Image(appInfo.images[index])
                    .resizable()
                    .scaledToFill()
                    .frame(width: 80, height: 80)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color.white, lineWidth: 2))
                    .offset(x: circlesAppeared ? 0 : CGFloat(index * 100))
                    .opacity(circlesAppeared ? 1 : 0)
            }
        }
        .padding(.top)
    }
    
    private var appDescriptionSection: some View {
        VStack(alignment: .leading, spacing: 15) {
            ForEach(aboutSections, id: \.self) { section in
                Text(section)
                    .font(.custom("IBMPlexMono-Medium", size: 18))
            }
        }
    }
    
    private var otherAppsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("My apps")
                .font(.custom("IBMPlexMono-Medium", size: 18))
            
            ForEach(otherApps) { app in
                AppLinkRow(app: app)
            }
        }
    }
}

struct AppInfo {
    let creatorName: String
    let description: String
    let images: [String]
}

struct AppLink: Identifiable {
    let id = UUID()
    let name: String
    let description: String
    let iconName: String
    let url: URL
    let isSystemIcon: Bool
    
    init(name: String, description: String, iconName: String, url: URL, isSystemIcon: Bool = true) {
        self.name = name
        self.description = description
        self.iconName = iconName
        self.url = url
        self.isSystemIcon = isSystemIcon
    }
}

struct AppLinkRow: View {
    let app: AppLink
    
    var body: some View {
        Link(destination: app.url) {
            HStack {
                iconView
                    .foregroundColor(.white)
                    .frame(width: 30, height: 30)
                    .background(Color.blue)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                
                VStack(alignment: .leading) {
                    Text(app.name)
                        .font(.custom("IBMPlexMono-Bold", size: 18))
                    Text(app.description)
                        .font(.custom("IBMPlexMono-Medium", size: 14))
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .foregroundColor(.gray)
            }
            .padding()
            .background(Color(.secondarySystemBackground))
            .cornerRadius(10)
        }
        .pressable()
    }
    
    @ViewBuilder
    private var iconView: some View {
        if app.isSystemIcon {
            Image(systemName: app.iconName)
        } else {
            Image(app.iconName)
                .resizable()
                .scaledToFit()
        }
    }
}


struct DevAbout: View {
    let appInfo = AppInfo(
        creatorName: "J.T",
        description: "I created SnipKey to make accessing text and images easier. It’s a tool designed to eliminate the hassle of copying and pasting across apps while ensuring your data stays private.",
        images: ["jt-dev", "snipkey-icon-new"]
    )

    let aboutSections = [
        "Hi, I'm JT! 👋",
        "I created SnipKey to streamline how I access and manage snippets of text and images.",
        "As a solo developer, I built SnipKey without tracking or ads, and it's completely free—because everyone deserves a secure tool without a paywall! ✨",
        "SnipKey is now open source! You can view the full source code, report issues, and contribute on GitHub. I believe in transparency and community-driven development. 🛠️",
        "I'll continue maintaining SnipKey for as long as I use it, ensuring it remains a reliable and free tool for everyone.",
        "With SnipKey, you can easily store and retrieve your snippets directly from your keyboard, keeping everything at your fingertips."
    ]
    
    let otherLinks = [
        AppLink(name: "Hit21", description: "Minimalistic Blackjack - Free", iconName: "hit21-icon", url: URL(string: "https://go.jrtv.space/hit21-download")!, isSystemIcon: false),
        AppLink(name: "More Free Apps", description: "Browse all my published apps", iconName: "store-icon", url: URL(string: "https://go.jrtv.space/apps")!, isSystemIcon: false),
        AppLink(name: "SnipKey on GitHub", description: "Open source — contribute or star the project", iconName: "chevron.left.forwardslash.chevron.right", url: URL(string: "https://github.com/jtvargas/SnipKey")!, isSystemIcon: true),

    ]
    
    
    var body: some View {
        AboutView(
            appInfo: appInfo,
            otherApps: otherLinks,
            aboutSections: aboutSections
        )
    }
}

#Preview {
    DevAbout()
}
