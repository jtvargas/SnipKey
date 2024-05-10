//
//  HomeTip.swift
//  SnipKey
//
//  Created by Jonathan Taveras Vargas on 5/9/24.
//

import Foundation
import TipKit

struct CreateSnippetTip: Tip {
    @Parameter
      static var alreadyDiscovered: Bool = false

    var title: Text {
        Text("Add Snippet")
    }
    
    var message: Text? {
        Text("Tap to add a new snippet.")
    }
    
    var rules: [Rule] {
       [
         #Rule(Self.$alreadyDiscovered) { $0 == false }
       ]
     }
}
