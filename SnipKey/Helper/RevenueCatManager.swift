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
    
    @Published var packages: [Package] = []
    @Published var currentOffering: Offering?
    @Published var customerInfo: CustomerInfo?
    @Published var isSubscribedToPro: Bool = false
    @Published var tips: [Package] = []
    
    private init() {
        setupRevenueCat()
    }
    
    private func setupRevenueCat() {
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
                }
            } else if let error = error {
                print("Error fetching offerings: \(error.localizedDescription)")
            }
        }
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
