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
                    Image("icon-snipkey")
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
            VStack(alignment: .leading) {
                Text("What you can do?")
                    .font(.custom("IBMPlexMono-Medium", size: 18))
                    .padding(.horizontal)
                    .padding(.bottom)

                
                ForEach(features) { feature in
                    VStack(alignment: .leading) {
                        HStack {
                            if let icon = feature.icon {
                                Image(systemName: icon)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 30, alignment: .center)
                                    .clipped()
                                    .foregroundStyle(color ?? Color.blue)
                                    .padding(.trailing, 15)
                                    .padding(.vertical, 10)
                            }
                            VStack(alignment: .leading) {
                                Text(feature.title)
                                    .fontWeight(.bold)
                                    .font(.custom("IBMPlexMono-Medium", size: 16))
                                Text(feature.description)
                            }
                            Spacer()
                        }
                        .font(.custom("IBMPlexMono-Medium", size: 14))
                    }
                    .padding(.horizontal,20)
                    .padding(.bottom, 20)
                }
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
        Feature(title: "Create Snippets", description: "Craft and instantly use shortcuts across apps.", icon: "doc.on.doc.fill"),
        Feature(title: "Tag & Organize", description: "Sort snippets swiftly with tags.", icon: "tag.fill"),
        Feature(title: "Keyboard Quick-Use", description: "Easily toggle SnipKey for fast typing aid.", icon: "keyboard.fill"),
        Feature(title: "Lock Snippets", description: "Secure sensitive data with encryption and biometrics.", icon: "lock.fill"),
    ], color: Color.label)
}
