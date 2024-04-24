//
//  KeyboardStatusView.swift
//  SnipKey
//
//  Created by Jonathan Taveras Vargas on 3/29/24.
//

import SwiftUI

struct KeyboardStatusView: View {
    var isActive: Bool = false
    var onKeyboardStatusPress: () -> Void
    
    var body: some View {
        
        Button(
            action: onKeyboardStatusPress,
            label: {
                VStack {
                    VStack(alignment: .leading) {
                        Text("Keyboard Status:")
                        HStack {
                            Image(systemName: "circle.fill")
                                .foregroundColor(isActive ? Color.customSuccess : Color.customError)
                                .symbolEffect(.pulse)
                            
                            Text(isActive ? "Ready to use" : "Not Active - Press here to activate")
                                .font(.custom("IBMPlexMono-Bold", size: 12))
                            
                           
                        }
                        
                        if checkFullAccess() {
                            Label("Everything setup!", systemImage: "info.square.fill")
                                .padding(.top)
                                .foregroundColor(Color.secondaryLabel)
                                .symbolEffect(.pulse)
                        } else {
                            Label("Images need Full Access enabled", systemImage: "info.square.fill")
                                .padding(.top)
                                .foregroundColor(Color.secondaryLabel)
                                .symbolEffect(.pulse)
                        }
                        
                       
                    }
                    .padding()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .border(Color.secondarySystemBackground, width: 4)
                .padding()
                .font(.custom("IBMPlexMono-Bold", size: 14))
                .tint(Color.label)
            })
        
    }
}

#Preview {
    func handleOnKeyboardStatusPress() {
        print("Keyboard Status press")
    }
    return KeyboardStatusView(isActive: false, onKeyboardStatusPress: handleOnKeyboardStatusPress)
}
