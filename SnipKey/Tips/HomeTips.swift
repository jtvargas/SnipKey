//
//  HomeTip.swift
//  SnipKey
//
//  Created by Jonathan Taveras Vargas on 5/9/24.
//

import Foundation
import TipKit

struct CloudIndicatorTip: Tip {
    @Parameter
    static var showiCloudTip: Bool = false

    var title: Text {
        Text("iCloud Sync")
    }
    
    var message: Text? {
        Text("Your Snippets are securely synced across all your devices via iCloud.")
    }
    
    var rules: [Rule] {
       [
         #Rule(Self.$showiCloudTip) { $0 == true }
       ]
     }
}

struct ConsiderTipDev: Tip {
    @Parameter
      static var alreadyDiscovered: Bool = false
    
    static let didCreateSnippetTrigger = Event(id: "didCreateSnippetTrigger")

    var title: Text {
        Text("Support Future Development")
    }

    var message: Text? {
        Text("If the app has been useful to you, consider leaving a rating or tip to help the developer continue improving and maintaining it.")
    }
    
    var actions: [Action] {
        Action(id: "support", title: "Support")
    }
    
    var rules: [Rule] {
       [
        #Rule(Self.didCreateSnippetTrigger) {
            // Set the conditions for when the tip displays.
            $0.donations.count >= 3
        }
       ]
     }
}


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
