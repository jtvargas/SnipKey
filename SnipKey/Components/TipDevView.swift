//
//  TipDevView.swift
//  SnipKey
//
//  Created by Jonathan Taveras Vargas on 9/27/24.
//

import SwiftUI
import Pow
import RevenueCat


enum TipDevJar: String, CaseIterable, Identifiable, Codable {
    var id: String { self.rawValue }
    
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
            return "🙌"
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
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject private var revenueCat: RevenueCatManager
    
    @State private var isButtonEnabled: Bool = true
    @State private var showConfetti: Bool = false
    @State private var showThankYou: Bool = false
    @State private var purchasedTip: TipDevJar? = nil
    /// True when the most recent successful purchase was the monthly supporter subscription,
    /// so the thank-you overlay shows a supporter-specific message instead of a tip message.
    @State private var purchasedSupporter: Bool = false
    
    // Grid tips (excluding contributor)
    private let gridTips: [TipDevJar] = [.candy, .juice, .taco, .ramen, .burger, .caviar]

    /// The developer's App Store page — surfaced under the review CTA so users can discover the
    /// other apps I ship. Opened via the SwiftUI `openURL` environment.
    private let developerAppsURL = URL(string: "https://apps.apple.com/us/developer/jonathan-taveras/id1270478820")!
    
    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]
    
    var body: some View {
        ZStack {
            // Background
            Color.systemBackground
                .ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 20) {
                    // Header
                    headerSection

                    // Message
                    messageSection

                    // Tips Grid
                    tipsGridSection

                    // Monthly subscription to fund ongoing development
                    monthlySupporterSection

                    // Review Button
                    reviewButton

                    // Discover the developer's other App Store apps
                    otherAppsSection
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 24)
            }
            // Keep the original non-scrolling look on normal devices; only scroll (no bounce)
            // when the content is taller than the sheet, e.g. on small phones.
            .scrollBounceBehavior(.basedOnSize)
            .task {
                // Reflect an existing supporter subscription when the sheet opens.
                await revenueCat.refreshCustomerInfo()
            }
            
            // Thank You Overlay
            if showThankYou {
                thankYouOverlay
            }
        }
        .changeEffect(
            .spray(origin: .center) {
                Group {
                    Image(systemName: "star.fill")
                        .foregroundStyle(.yellow)
                    Image(systemName: "sparkle")
                        .foregroundStyle(.orange)
                    Image(systemName: "gift.fill")
                        .foregroundStyle(.yellow.opacity(0.8))
                }
            },
            value: showConfetti
        )
    }
    
    // MARK: - Header Section
    private var headerSection: some View {
        VStack(spacing: 12) {
            // App Icon with yellow glow
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color.yellow.opacity(0.3), Color.clear],
                            center: .center,
                            startRadius: 20,
                            endRadius: 50
                        )
                    )
                    .frame(width: 90, height: 90)
                
                Image("snipkey-icon-new")
                    .resizable()
                    .frame(width: 60, height: 60)
                    .cornerRadius(14)
                    .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 4)
            }
            
            Text("Support SnipKey")
                .font(.custom("IBMPlexMono-Bold", size: 22))
                .foregroundColor(.label)
        }
    }
    
    // MARK: - Message Section
    private var messageSection: some View {
        Text("I'm an indie dev building **SnipKey** for free. If the app helps you, consider leaving a tip or review!")
            .font(.custom("IBMPlexMono-Regular", size: 12))
            .multilineTextAlignment(.center)
            .foregroundColor(.secondaryLabel)
            .lineSpacing(3)
            .padding(.horizontal, 8)
    }
    
    // MARK: - Tips Grid Section
    private var tipsGridSection: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(gridTips) { tipJar in
                if let package = revenueCat.tips.first(where: { $0.storeProduct.productIdentifier == tipJar.productId }) {
                    TipGridCell(
                        emoji: tipJar.emoji,
                        name: tipJar.name,
                        price: package.localizedPriceString,
                        isEnabled: isButtonEnabled
                    ) {
                        handlePurchase(tipJar: tipJar, package: package)
                    }
                } else {
                    // Fallback with test price if package not loaded
                    TipGridCell(
                        emoji: tipJar.emoji,
                        name: tipJar.name,
                        price: tipJar.priceTest,
                        isEnabled: false
                    ) { }
                }
            }
        }
    }
    
    // MARK: - Monthly Supporter Section
    /// Prominent solid-yellow CTA (the screen's accent) inviting users to fund monthly development.
    /// Shows a non-tappable "active" card instead once the user has the `snip_support` subscription.
    @ViewBuilder
    private var monthlySupporterSection: some View {
        if revenueCat.isMonthlySupporter {
            monthlySupporterActiveCard
        } else {
            monthlySupporterButton
        }
    }

    private var monthlySupporterButton: some View {
        Button(action: {
            handleSupporterPurchase()
        }) {
            HStack(spacing: 12) {
                Image(systemName: "heart.fill")
                    .font(.system(size: 18))

                VStack(alignment: .leading, spacing: 2) {
                    Text("Monthly Supporter")
                        .font(.custom("IBMPlexMono-Bold", size: 15))
                    Text("Help fund ongoing development")
                        .font(.custom("IBMPlexMono-Regular", size: 11))
                        .foregroundColor(.black.opacity(0.7))
                }

                Spacer()

                if let supporter = revenueCat.supporterPackage {
                    Text("\(supporter.localizedPriceString)/mo")
                        .font(.custom("IBMPlexMono-Bold", size: 14))
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .padding(.horizontal, 16)
            .background(Color.yellow)
            .foregroundColor(.black)
            .cornerRadius(12)
        }
        .pressable()
        // Disabled until the Support offering loads, or while a purchase is in flight.
        .disabled(revenueCat.supporterPackage == nil || !isButtonEnabled)
        .opacity((revenueCat.supporterPackage == nil || !isButtonEnabled) ? 0.6 : 1)
    }

    private var monthlySupporterActiveCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "heart.fill")
                .font(.system(size: 18))
                .foregroundColor(.yellow)

            VStack(alignment: .leading, spacing: 2) {
                Text("You're a Monthly Supporter 💛")
                    .font(.custom("IBMPlexMono-Bold", size: 15))
                    .foregroundColor(.label)
                Text("Thank you for funding development")
                    .font(.custom("IBMPlexMono-Regular", size: 11))
                    .foregroundColor(.secondaryLabel)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.yellow.opacity(0.15))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.yellow.opacity(0.5), lineWidth: 1.5)
        )
    }

    // MARK: - Review Button
    private var reviewButton: some View {
        Button(action: {
            requestReview()
        }) {
            HStack(spacing: 8) {
                Image(systemName: "star.fill")
                    .font(.system(size: 14))
                Text("Leave a Review")
                    .font(.custom("IBMPlexMono-SemiBold", size: 14))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color.label)
            .foregroundColor(.systemBackground)
            .cornerRadius(12)
        }
        .pressable()
    }

    // MARK: - Other Apps Section
    /// A muted caption + outlined CTA (matched to `reviewButton`'s shape) that opens the
    /// developer's App Store page. Outlined rather than solid so it reads as secondary to
    /// "Leave a Review" while staying part of the same yellow-accented design language.
    private var otherAppsSection: some View {
        VStack(spacing: 8) {
            HStack {
                Text("I have a few more apps if you're curious:")
                    .font(.custom("IBMPlexMono-SemiBold", size: 12))
                    .foregroundColor(.secondaryLabel)
                Spacer()
            }

            otherAppsButton
        }
    }

    private var otherAppsButton: some View {
        Button(action: {
            openURL(developerAppsURL)
        }) {
            HStack(spacing: 8) {
                Image(systemName: "square.grid.2x2.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.yellow)
                Text("Check Out My Other Apps")
                    .font(.custom("IBMPlexMono-SemiBold", size: 14))
                    .foregroundColor(.label)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondaryLabel)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.secondarySystemBackground.opacity(0.5))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.yellow.opacity(0.5), lineWidth: 1.5)
            )
        }
        .pressable()
    }
    
    // MARK: - Thank You Overlay
    private var thankYouOverlay: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        showThankYou = false
                    }
                }
            
            VStack(spacing: 16) {
                // Star icon
                ZStack {
                    Circle()
                        .fill(Color.yellow.opacity(0.2))
                        .frame(width: 80, height: 80)
                    
                    Image(systemName: "star.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(Color.yellow)
                        .symbolEffect(.pulse)
                }
                
                VStack(spacing: 8) {
                    Text("Thank You!")
                        .font(.custom("IBMPlexMono-Bold", size: 24))
                        .foregroundColor(.label)
                    
                    if purchasedSupporter {
                        Text("Your monthly support funds ongoing development 💛")
                            .font(.custom("IBMPlexMono-Medium", size: 13))
                            .foregroundColor(.secondaryLabel)
                            .multilineTextAlignment(.center)
                    } else if let tip = purchasedTip {
                        Text("Your \(tip.emoji) \(tip.name) tip means the world!")
                            .font(.custom("IBMPlexMono-Medium", size: 13))
                            .foregroundColor(.secondaryLabel)
                            .multilineTextAlignment(.center)
                    }

                    Text("You're helping keep SnipKey alive!")
                        .font(.custom("IBMPlexMono-Regular", size: 12))
                        .foregroundColor(.secondaryLabel)
                        .multilineTextAlignment(.center)
                }
                
                VStack(spacing: 10) {
                    // Optional: Leave 5 Stars button
                    Button(action: {
                        requestReview()
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                            showThankYou = false
                        }
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "star.fill")
                                .font(.system(size: 12))
                            Text("Leave 5 Stars")
                                .font(.custom("IBMPlexMono-SemiBold", size: 14))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.yellow)
                        .foregroundColor(.black)
                        .cornerRadius(10)
                    }
                    
                    // Close button
                    Button(action: {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                            showThankYou = false
                        }
                    }) {
                        Text("Close")
                            .font(.custom("IBMPlexMono-Medium", size: 14))
                            .foregroundColor(.secondaryLabel)
                            .padding(.vertical, 8)
                    }
                }
                .padding(.top, 4)
            }
            .padding(24)
            .frame(maxWidth: 300)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.systemBackground)
                    .shadow(color: .black.opacity(0.2), radius: 20, x: 0, y: 10)
            )
            .transition(.scale.combined(with: .opacity))
        }
    }
    
    // MARK: - Handle Purchase
    private func handlePurchase(tipJar: TipDevJar, package: RevenueCat.Package) {
        guard isButtonEnabled else { return }
        
        isButtonEnabled = false
        
        revenueCat.purchase(package: package) { success in
            if success {
                purchasedSupporter = false
                purchasedTip = tipJar

                // Show confetti first
                withAnimation {
                    showConfetti.toggle()
                }

                // Then show thank you overlay after a short delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                        showThankYou = true
                    }
                }
            }

            // Re-enable buttons after a delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                isButtonEnabled = true
            }
        }
    }

    // MARK: - Handle Supporter Subscription
    /// Purchase the monthly supporter subscription. Mirrors `handlePurchase` (shared confetti +
    /// thank-you overlay + button gating) but uses the supporter-specific success message.
    private func handleSupporterPurchase() {
        guard isButtonEnabled, let package = revenueCat.supporterPackage else { return }

        isButtonEnabled = false

        revenueCat.purchase(package: package) { success in
            if success {
                purchasedTip = nil
                purchasedSupporter = true

                withAnimation {
                    showConfetti.toggle()
                }

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                        showThankYou = true
                    }
                }
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                isButtonEnabled = true
            }
        }
    }
}

// MARK: - Tip Grid Cell Component
struct TipGridCell: View {
    let emoji: String
    let name: String
    let price: String
    var isEnabled: Bool = true
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Text(emoji)
                    .font(.system(size: 28))
                
                Text(name)
                    .font(.custom("IBMPlexMono-SemiBold", size: 11))
                    .foregroundColor(.label)
                    .lineLimit(1)
                
                Text(price)
                    .font(.custom("IBMPlexMono-Bold", size: 12))
                    .foregroundColor(.yellow)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.secondarySystemBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.yellow.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.6)
    }
}

#Preview {
    TipDevView()
        .environmentObject(RevenueCatManager.shared)
}
