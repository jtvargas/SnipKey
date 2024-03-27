//
//  Item.swift
//  SnipKey
//
//  Created by Jonathan Taveras Vargas on 3/25/24.
//

import Foundation
import SwiftData

@Model
final class SnippetItem {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}

extension SnippetItem {
    static var dummy: SnippetItem {
        .init(timestamp: .now)
    }
}
