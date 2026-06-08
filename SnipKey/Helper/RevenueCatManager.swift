//
//  RevenueCatManager.swift
//  SnipKey
//
//  Created by Jonathan Taveras Vargas on 9/27/24.
//

import Foundation
import RevenueCat
import SwiftUI

class RevenueCatManager: ObservableObject {
    static let shared = RevenueCatManager()

    /// Product identifier + offering for the monthly "Support the developer" subscription.
    /// Lives in a dedicated named offering, separate from `offerings.current` (which feeds tips).
    static let supporterProductID = "snip_support"
    static let supporterOfferingID = "Support"

    @Published var packages: [Package] = []
    @Published var currentOffering: Offering?
    @Published var customerInfo: CustomerInfo?
    @Published var isSubscribedToPro: Bool = false
    @Published var tips: [Package] = []

    /// The monthly supporter subscription package, resolved from the `Support` offering.
    @Published var supporterPackage: Package?

    /// True while the user has an active `snip_support` subscription. Derived from
    /// `customerInfo.activeSubscriptions` so it needs no entitlement identifier.
    @Published var isMonthlySupporter: Bool = false

    private init() {
        setupRevenueCat()
    }
    
    private func setupRevenueCat() {
        // This is a RevenueCat PUBLIC API key (prefixed "appl_"). By RevenueCat's design,
        // public keys are intended to ship in client apps — they can only fetch offerings
        // and process purchases, not access the dashboard or modify account settings.
        // The tip jar will not load products if this key is replaced or removed.
        Purchases.configure(withAPIKey: "appl_otSqwAryUYKsMuWwBCACxYdwYuT")
        self.fetchOfferings()
//        Purchases.shared.delegate = self
    }
    
    func fetchOfferings() {
        Purchases.shared.getOfferings { (offerings, error) in
            if let offerings = offerings {
                DispatchQueue.main.async {
                    self.currentOffering = offerings.current
                    self.packages = offerings.current?.availablePackages ?? []
                    self.fetchTipProducts()
                    self.fetchSupporterPackage(from: offerings)
                }
            } else if let error = error {
                print("Error fetching offerings: \(error.localizedDescription)")
            }
        }
    }

    /// Resolve the monthly supporter package from the dedicated `Support` offering. It is NOT part
    /// of `offerings.current`, so it must be read by name. Prefer the exact `snip_support` product,
    /// then fall back to the offering's monthly / first package so a dashboard tweak won't break it.
    private func fetchSupporterPackage(from offerings: Offerings) {
        let support = offerings.offering(identifier: Self.supporterOfferingID)
        self.supporterPackage = support?.availablePackages.first {
            $0.storeProduct.productIdentifier == Self.supporterProductID
        } ?? support?.monthly ?? support?.availablePackages.first
    }
    
    func fetchTipProducts() {
            self.tips = self.packages.filter { package in
                package.storeProduct.productIdentifier.lowercased().contains("tip")
            }
        }
    
    func purchase(package: Package, completion: ((Bool) -> Void)? = nil) {
        Purchases.shared.purchase(package: package) { (transaction, customerInfo, error, userCancelled) in
            if let customerInfo = customerInfo, !userCancelled, error == nil {
                DispatchQueue.main.async {
                    self.customerInfo = customerInfo
                    self.isMonthlySupporter = customerInfo.activeSubscriptions.contains(Self.supporterProductID)
                    completion?(true)
                }
                print("Purchase successful!")
            } else if let error = error {
                print("Error making purchase: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    completion?(false)
                }
            } else {
                DispatchQueue.main.async {
                    completion?(false)
                }
            }
        }
    }
    
    func restorePurchases() {
        Purchases.shared.restorePurchases { (customerInfo, error) in
            if let customerInfo = customerInfo {
                DispatchQueue.main.async {
                    self.customerInfo = customerInfo
                }
                print("Purchases restored!")
            } else if let error = error {
                print("Error restoring purchases: \(error.localizedDescription)")
            }
        }
    }
    
    func checkSubscriptionStatus() async {
        do {
            let customerInfo = try await Purchases.shared.customerInfo()
//            DispatchQueue.main.async {
//                self.isSubscribedToPro = customerInfo.entitlements.all["pro"]?.isActive == true
//            }
            self.isSubscribedToPro = customerInfo.entitlements.all["pro"]?.isActive == true
        } catch {
//            DispatchQueue.main.async {
//                self.isSubscribedToPro = false
//            }
            self.isSubscribedToPro = false
        }

    }

    /// Refresh `customerInfo` and the derived `isMonthlySupporter` flag. Cheap to call on view
    /// appearance — RevenueCat serves a cached `CustomerInfo` and only hits the network when stale.
    @MainActor
    func refreshCustomerInfo() async {
        do {
            let info = try await Purchases.shared.customerInfo()
            self.customerInfo = info
            self.isMonthlySupporter = info.activeSubscriptions.contains(Self.supporterProductID)
        } catch {
            print("Error refreshing customer info: \(error.localizedDescription)")
        }
    }
}

//extension RevenueCatManager: PurchasesDelegate {
//    func purchases(_ purchases: Purchases, receivedUpdated customerInfo: CustomerInfo) {
//        DispatchQueue.main.async {
//            self.customerInfo = customerInfo
//        }
//    }
//}

// MARK: - SwiftUI View Extensions

extension View {
    func withRevenueCat() -> some View {
        self.environmentObject(RevenueCatManager.shared)
    }
}

// Usage in your main app:
// @main
// struct YourApp: App {
//     var body: some Scene {
//         WindowGroup {
//             ContentView()
//                 .withRevenueCat()
//         }
//     }
// }

// Usage in a view:
// struct ContentView: View {
//     @EnvironmentObject private var revenueCat: RevenueCatManager
//
//     var body: some View {
//         // Your view content
//     }
// }
