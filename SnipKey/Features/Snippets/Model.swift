//
//  Item.swift
//  SnipKey
//
//  Created by Jonathan Taveras Vargas on 3/25/24.
//

import Foundation
import SwiftData

enum SnipType: Codable {
    case txt
    case url
}

enum Tags: String, CaseIterable, Identifiable, Codable   {
    case none, personal, work
    var id: String { return self.rawValue }
}

@Model
final class SnippetItem {
    var timestamp: Date
    var id: String
    var title: String
    var content: String
    var tag: Tags
    var type: SnipType
    
    init(title: String, content: String, tag: Tags? , type: SnipType) {
        self.timestamp =  Date()
        self.id = UUID().uuidString + title.hmac(key: "SnipKeyApp") // create SHA-256 more unique id creation
        self.title = title
        self.content = content
        self.tag = tag ?? Tags.none
        self.type = type
    }
}

extension SnippetItem {
    static var dummy: SnippetItem {
        .init(title: "Dummy Test", content: "Dummy Content", tag: nil, type: .url)
    }
}
