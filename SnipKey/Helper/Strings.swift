//
//  Strings.swift
//  SnipKey
//
//  Created by Jonathan Taveras Vargas on 3/28/24.
//

import Foundation
import CommonCrypto

extension String {
    func hmac(key: String) -> String {
        var digest = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        CCHmac(CCHmacAlgorithm(kCCHmacAlgSHA256), key, key.count, self, self.count, &digest)
        let data = Data()
        return data.map { String(format: "%02hhx", $0) }.joined()
    }

}
