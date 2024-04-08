//
//  Biometrics.swift
//  SnipKey
//
//  Created by Jonathan Taveras Vargas on 4/8/24.
//

import Foundation
import LocalAuthentication


class DeviceBiometrics {
    let context = LAContext()
    var hasBiometricsCapability: Bool
    var error: NSError?
    let reason = "We need to unlock your data."
    
    init(){
        self.hasBiometricsCapability = context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error)
    }
    
    func authenticate(successHandler: @escaping () -> Void, unSuccessHandler: @escaping (Error?) -> Void) {
        if self.hasBiometricsCapability {
            context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { success, authenticationError in
                // Authentication has now completed
                if success {
                    // Authenticated successfully
                    successHandler()
                } else {
                    // There was a problem
                    unSuccessHandler(authenticationError)
                }
            }
        } else {
            // Handle the case where biometrics capability is not available
            // For example, you might want to call unSuccessHandler with a specific error
            unSuccessHandler(NSError(domain: "com.yourdomain", code: -1, userInfo: [NSLocalizedDescriptionKey: "Biometrics capability is not available."]))
        }
    }
}
