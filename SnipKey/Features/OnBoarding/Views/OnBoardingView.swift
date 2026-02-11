//
//  OnboardingView.swift
//
//  Created by Adam Lyttle on 2/5/2023.
//
//  adamlyttleapps.com
//  twitter.com/adamlyttleapps
//
//  Usage:
/*
 OnboardingView(appName: "Real Estate Calculator", features: [
 Feature(title: "Mortgage Repayments", description: "Easily calculate weekly, monthly and yearly repayments ", icon: "house"),
 Feature(title: "Amortization", description: "Quickly view amortization for the life of the loan", icon: "chart.line.downtrend.xyaxis"),
 Feature(title: "Deposit Calculator", description: "Calculate deposit based on purchase price and savings", icon: "percent"),
 Feature(title: "Ad-Free Experience", description: "Thank you for downloading my app, I hope you enjoy it :-)", icon: "party.popper"),
 ], color: Color.blue)
 */

import SwiftUI

struct Feature: Identifiable {
    let id = UUID()
    let title: String
    let description: String
    let icon: String?
}

struct OnboardingView: View {
    @Environment(\.colorScheme) var colorScheme
    @AppStorage("showAboutApp") var showAboutApp: Bool = false
    
    @State var appName: String
    
    @Binding var showOnboarding: Bool
    
    let features: [Feature]
    let color: Color?
    var body: some View {
        ZStack{
        VisualEffectView(effect: UIBlurEffect(style: colorScheme == .dark ? .dark : .light))
                     .edgesIgnoringSafeArea(.all)
        VStack {
            Group{
                HStack{
                    Image("snipkey-icon-new")
                        .resizable()
                        .frame(width: 65, height: 68)
                        .clipShape(RoundedRectangle( cornerRadius: 6))
                    
                    Text("\(appName)")
                        .font(.custom("IBMPlexMono-Medium", size: 28))
                        .fontWeight(.bold)
                        .multilineTextAlignment(.leading)
                        
                }
                .padding(.top, 50)
            }
            
            Spacer()
            VStack(alignment: .leading, spacing: 0) {
                Text("What you can do?")
                    .font(.custom("IBMPlexMono-Medium", size: 18))
                    .padding(.horizontal)
                    .padding(.bottom, 10)

                
                ForEach(features) { feature in
                    HStack(spacing: 12) {
                        if let icon = feature.icon {
                            Image(systemName: icon)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 24, height: 24)
                                .foregroundStyle(color ?? Color.blue)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(feature.title)
                                .font(.custom("IBMPlexMono-SemiBold", size: 14))
                            Text(feature.description)
                                .font(.custom("IBMPlexMono-Regular", size: 12))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                }
                Button {
                    showOnboarding = false
                    showAboutApp = true
                } label: {
                    Label("About the App", systemImage: "questionmark.circle.fill")
                        .foregroundStyle(.blue.gradient)
                        .underline()
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .buttonStyle(.plain)
            }
            Spacer()
            VStack {
                ZStack {
                    Rectangle()
                        .foregroundColor(Color.secondarySystemBackground)
                        .cornerRadius(12)
                        .frame(height: 54)
                    Text("Close")
                        .fontWeight(.bold)
                        .foregroundColor(.label)
                }
                .bold()
                .font(.custom("IBMPlexMono-Medium", size: 16))
                .onDisappear() {
                    showOnboarding = false
                }
                .onTapGesture {
                    showOnboarding = false
                }
            }
            .padding(.top, 15)
            .padding(.bottom, 50)
            .padding(.horizontal,15)
        }
            
        .padding()
        }
        .presentationBackground(Color.clear)
    }
    
}


#Preview {
    @State var showOnboarding = false
    return OnboardingView(appName: "SnipKey", showOnboarding: $showOnboarding, features: [
        Feature(title: "Snippets", description: "Save text, URLs, images and PDFs.", icon: "doc.on.doc.fill"),
        Feature(title: "Keyboard", description: "Access snippets from any app.", icon: "keyboard.fill"),
        Feature(title: "Slash Commands", description: "Type / to find and paste snippets.", icon: "chevron.left.forwardslash.chevron.right"),
        Feature(title: "Tags", description: "Organize with custom tags.", icon: "tag.fill"),
        Feature(title: "Biometric Lock", description: "Secure snippets with FaceID.", icon: "lock.fill"),
        Feature(title: "iCloud Sync", description: "Syncs across all your devices.", icon: "cloud.fill"),
        Feature(title: "Open Source", description: "View code on GitHub.", icon: "curlybraces"),
    ], color: Color.label)
}
