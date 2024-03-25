//
//  Item.swift
//  SnipKey
//
//  Created by Jonathan Taveras Vargas on 3/25/24.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
