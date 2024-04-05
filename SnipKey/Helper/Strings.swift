//
//  Strings.swift
//  SnipKey
//
//  Created by Jonathan Taveras Vargas on 3/28/24.
//

import Foundation
import CommonCrypto
import UIKit

extension String {
    func hmac(key: String) -> String {
        var digest = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        CCHmac(CCHmacAlgorithm(kCCHmacAlgSHA256), key, key.count, self, self.count, &digest)
        let data = Data()
        return data.map { String(format: "%02hhx", $0) }.joined()
    }
    
    func isValidURL() -> Bool {
        var urlString = self
        
        if urlString.isEmpty {
            return false
        }
        
        if !urlString.lowercased().hasPrefix("https://") {
            urlString = "https://" + urlString
        }
        
        guard let url = URL(string: urlString) else {
            return false
        }
        
        return UIApplication.shared.canOpenURL(url)
    }
    
    func getValidURLString() -> String {
        var urlString = self
        
        if urlString.isEmpty {
            return ""
        }
        
        if !urlString.lowercased().hasPrefix("https://") {
            urlString = "https://" + urlString
        }
        
        guard let url = URL(string: urlString) else {
            return ""
        }
        
        return  UIApplication.shared.canOpenURL(url) ? urlString : ""
    }
}
