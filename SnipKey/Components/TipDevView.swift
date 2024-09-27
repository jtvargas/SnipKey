//
//  TipDevView.swift
//  SnipKey
//
//  Created by Jonathan Taveras Vargas on 9/27/24.
//

import SwiftUI


enum TipDevJar: String, CaseIterable, Identifiable, Codable {
    var id: String {  self.rawValue }
    
    case candy, juice, taco, ramen, burger, caviar, contributor
    

    var name: String {
        self.rawValue.capitalized
    }
    
    var emoji: String {
        switch self {
        case .candy:
            return "🍬"
        case .juice:
             return "🧃"
        case .taco:
            return "🌮"
        case .ramen:
            return "🍜"
        case .burger:
            return "🍔"
        case .caviar:
           return "🍣"
        case .contributor:
           return "🙌 - Monthly"
        }
    }
    
    var priceTest: String {
        switch self {
        case .candy:
            return "$1.99"
        case .juice:
            return "$4.99"
        case .taco:
            return "$9.99"
        case .ramen:
            return "$14.99"
        case .burger:
            return "$29.99"
        case .caviar:
            return "$99.99"
        case .contributor:
            return "$2.99"
        }
    }
    
    
    var productId: String {
        switch self {
        case .candy:
            return "sk_199_tip"
        case .juice:
            return "sk_499_tip"
        case .taco:
            return "sk_999_tip"
        case .ramen:
            return "sk_1499_tip"
        case .burger:
            return "sk_2999_tip"
        case .caviar:
            return "sk_9999_tip"
        case .contributor:
            return "sk_support_tip"
        }
    }
    
}

struct TipDevView: View {
    @Environment(\.requestReview) var requestReview
    @EnvironmentObject private var revenueCat: RevenueCatManager
    
    var body: some View {
        ScrollView {
            Image("snipkey-icon-new")
                .resizable()
                .frame(width: 60, height: 60)
                .cornerRadius(12)
            Spacer(minLength: 20)
            Text("Support SnipKey")
                .font(.custom("IBMPlexMono-Bold", size: 21))
            Spacer(minLength: 20)
            Text("I'm just one person building **SnipKey**, a completely **free app** with no data stored on servers—everything stays on your device. \n\nIf **SnipKey helps you**, and you'd like to **support its development**, consider leaving a tip or a review. Either one would motivate me to continue supporting the app ❤️‍🩹")
                .font(.custom("IBMPlexMono-Medium", size: 12))
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Spacer(minLength: 20)
            VStack(spacing: 10) {
                ForEach(TipDevJar.allCases) { tipJar in
                    if let package = revenueCat.tips.first(where: { $0.storeProduct.productIdentifier == tipJar.productId }) {
                        supportButton(
                            emoji: tipJar.emoji,
                            text: tipJar.name,
                            price: package.localizedPriceString
                        ) {
                            revenueCat.purchase(package: package)
                        }
                    }
                }
            }
            
            Text("or")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Button(action: {
                requestReview()
            }) {
                Text("Write a Review")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.label.gradient)
                    .foregroundColor(.systemBackground) 
                    .cornerRadius(10)
            }
        }
        .font(.custom("IBMPlexMono-Bold", size: 16))
        .padding()
    }
    
    func supportButton(emoji: String, text: String, price: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(emoji)
                Text(text)
                Spacer()
                Text(price)
            }
            .font(Font.custom("Nunito-Bold", size: 16))
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.systemBackground)
            .clipShape(.capsule)
            .border(Color.label.gradient, width: 4)
            .foregroundColor(.label)
            .cornerRadius(6)
        }
        .pressable()
    }
}

#Preview {
    TipDevView()
//        .environmentObject(RevenueCatManager.shared)
}
