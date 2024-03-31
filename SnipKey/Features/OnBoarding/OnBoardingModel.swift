//
//  Model.swift
//  SnipKey
//
//  Created by Jonathan Taveras Vargas on 3/29/24.
//

import Foundation

// MARK: - Welcome Item
struct BoardingItem: Identifiable {
  var id = UUID()
  var title: String
  var information: String
  var image: String
  var darkImage: String?
}
