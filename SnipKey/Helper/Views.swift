//
//  Views.swift
//  SnipKey
//
//  Created by Jonathan Taveras Vargas on 3/29/24.
//

import Foundation
import SwiftUI

#if canImport(UIKit)
extension View {
    func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}
#endif

extension View {
    func limitText(_ text: Binding<String>, to characterLimit: Int) -> some View {
        self.onChange(of: text.wrappedValue, {
            text.wrappedValue = String(text.wrappedValue.prefix(characterLimit))
        })
    }
}
