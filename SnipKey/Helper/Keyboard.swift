//
//  Keyboard.swift
//  SnipKey
//
//  Created by Jonathan Taveras Vargas on 4/24/24.
//

import SwiftUI
import UIKit
import UniformTypeIdentifiers

func pasteFromClipboard() -> String {
    UIPasteboard.general.string ?? ""
}

func copyImageToClipboard(snippet: SnippetItem) -> Bool? {
    guard
        let newImage = UIImage(data: (snippet.file?.fileData)!)
    else { return nil }
    
    var imageData: Data?
    
    if snippet.file?.fileFormatType == "image/png"{
        imageData = newImage.pngData()
    }
    
    if snippet.file?.fileFormatType == "image/jpeg"{
        imageData = newImage.jpegData(compressionQuality: 0.5)
    }
    
    
    let clipboard = UIPasteboard.general
    clipboard.setValue(imageData!, forPasteboardType: UTType.png.identifier)
    
    return true
}



func checkFullAccess() -> Bool
{
    var hasFullAccess = false
    if #available(iOSApplicationExtension 10.0, *) {
        let pasty = UIPasteboard.general
        if pasty.hasURLs || pasty.hasColors || pasty.hasStrings || pasty.hasImages || pasty.value(forPasteboardType: UTType.pdf.identifier) != nil {
            hasFullAccess = true
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
