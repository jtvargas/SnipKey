//
//  Keyboard.swift
//  SnipKey
//
//  Created by Jonathan Taveras Vargas on 4/24/24.
//

import SwiftUI

func pasteFromClipboard() -> String {
    UIPasteboard.general.string ?? ""
}

func checkFullAccess() -> Bool
{
    var hasFullAccess = false
    if #available(iOSApplicationExtension 10.0, *) {
        let pasty = UIPasteboard.general
        if pasty.hasURLs || pasty.hasColors || pasty.hasStrings || pasty.hasImages {
            hasFullAccess = true
        } else {
            pasty.string = "TEST"
            if pasty.hasStrings {
                hasFullAccess = true
                pasty.string = ""
            }
        }
    } else {
        // Fallback on earlier versions
        var clippy : UIPasteboard?
        clippy = UIPasteboard.general
        if clippy != nil {
            hasFullAccess = true
        }
    }
    return hasFullAccess
}
