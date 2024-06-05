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

extension String {
    func toDetectedAttributedString() -> AttributedString {
        
        var attributedString = AttributedString(self)
        
        let types = NSTextCheckingResult.CheckingType.link.rawValue | NSTextCheckingResult.CheckingType.phoneNumber.rawValue
        
        guard let detector = try? NSDataDetector(types: types) else {
            return attributedString
        }
        
        let matches = detector.matches(in: self, options: [], range: NSRange(location: 0, length: count))
        
        for match in matches {
            let range = match.range
            let startIndex = attributedString.index(attributedString.startIndex, offsetByCharacters: range.lowerBound)
            let endIndex = attributedString.index(startIndex, offsetByCharacters: range.length)
            // Setting URL for link
            if match.resultType == .link, let url = match.url {
                attributedString[startIndex..<endIndex].link = url
                // If it's an email, set a background color
//                if url.scheme == "mailto" {
                attributedString[startIndex..<endIndex].foregroundColor = .blue
                attributedString[startIndex..<endIndex].underlineColor = .blue
//                }
            }
            // Setting URL for phone number
            if match.resultType == .phoneNumber, let phoneNumber = match.phoneNumber {
                let url = URL(string: "tel:\(phoneNumber)")
                attributedString[startIndex..<endIndex].link = url
            }
        }
        return attributedString
    }
}

