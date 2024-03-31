//
//  KeyboardView.swift
//  SnipKeyboard
//
//  Created by Jonathan Taveras Vargas on 3/31/24.
//

import SwiftUI
import SwiftData


class KeyboardObserver: ObservableObject {
    @Published var isShowing = false
    @Published var height: CGFloat = 0
    
    func addObserver() {
        NotificationCenter.default.addObserver(self, selector: #selector(self.keyboardWillShow(_:)), name: UIResponder.keyboardWillShowNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(self.keyboardWillHide(_:)), name: UIResponder.keyboardWillHideNotification, object: nil)
    }
    
    func removeObserver() {
        NotificationCenter.default.removeObserver(self,name: UIResponder.keyboardWillShowNotification,object: nil)
        NotificationCenter.default.removeObserver(self,name: UIResponder.keyboardWillHideNotification,object: nil)
    }
    
    @objc func keyboardWillShow(_ notification: Notification) {
        isShowing = true
        guard let userInfo = notification.userInfo as? [String: Any] else {
            return
        }
        guard let keyboardInfo = userInfo[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue else {
            return
        }
        let keyboardSize = keyboardInfo.cgRectValue.size
//        print("[keyboardWillShow] HEIGHT: \(keyboardSize.height)")
        height = keyboardSize.height
        
    }
    
    @objc func keyboardWillHide(_ notification: Notification) {
        isShowing = false
        height = 0
    }
}

let layout = [
    GridItem(.adaptive(minimum: 150, maximum: 175)),
    //    GridItem(.adaptive(minimum: 80, maximum: 120)),
]


struct SnippetImageKeyboard: View {
    var body: some View {
        Image(systemName:"character.cursor.ibeam" )
            .background(Color.black, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .foregroundStyle(.white)
    }
}

struct SnippetListItemKeyboard: View {
    
    var body: some View {
        HStack {
            SnippetImageKeyboard()
                .frame(width: 35, height: 35)
                .background(Color.black, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .foregroundStyle(.white)
            
            VStack {
                Text("Snippet Title")
                    .bold()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .tint(Color.black)
                    .bold()
                    .font(.custom("IBMPlexMono-Medium", size: 14))
                
                Text("#TAG")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .foregroundColor(Color.gray)
                    .font(.custom("IBMPlexMono-Medium", size: 12))
            }
        }
        
    }
}


struct OverflowContentViewModifier: ViewModifier {
    @State private var contentOverflow: Bool = false
    
    func body(content: Content) -> some View {
        GeometryReader { geometry in
            content
            .background(
                GeometryReader { contentGeometry in
                    Color.clear.onAppear {
                        contentOverflow = contentGeometry.size.height > geometry.size.height
                    }
                }
            )
            .wrappedInScrollView(when: contentOverflow)
        }
    }
}

extension View {
    @ViewBuilder
    func wrappedInScrollView(when condition: Bool) -> some View {
        if condition {
            ScrollView {
                self
            }
        } else {
            self
        }
    }
}

extension View {
    func scrollOnOverflow() -> some View {
        modifier(OverflowContentViewModifier())
    }
}


struct KeyboardView: View {
    @Environment(\.modelContext) var modelContext
    @Query(sort: \SnippetItem.timestamp, order: .reverse) private var snippetsTest: [SnippetItem]
    
    @State private var snippets = ["hello", "noway"]
    
    @ObservedObject var keyboard: KeyboardObserver = KeyboardObserver()
    
    @State private var text: String = ""
    let columns = [GridItem(.adaptive(minimum: 150, maximum: 175), spacing: 6)]
    
    func actionPerform() {
        print("snippets: \(snippetsTest)")
    }
    private func emoji(_ value: Int) -> String {
             guard let scalar = UnicodeScalar(value) else { return "?" }
             return String(Character(scalar))
         }
    
    @State private var favoriteColor = 0
    
    func sentValueToTextInput(value: String) {
        NotificationCenter.default.post(name: NSNotification.Name(rawValue: "addKey"), object: value)
    }

    var body: some View {
        
        VStack {
                ScrollView {
                    LazyVGrid(columns: columns) {
                        ForEach(snippets, id: \.self) { snippet in
                            GroupBox {
                                Button {
                                    sentValueToTextInput(value: "ok")
                                } label: {
                                    Text("hello")
                                        .font(.largeTitle)
                                        .fixedSize()
                                    Text("bye")
                                        .fixedSize()
                                }
                                
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .background(Color.green)
                }
            Button {
                actionPerform()
            } label: {
                Text("hello")
                    .font(.largeTitle)
                    .fixedSize()
            }
//            Picker("What is your favorite color?", selection: $favoriteColor) {
//                Image(systemName:"circle.fill").tag(0)
//                Text("Personal").tag(1)
//                Text("Work").tag(2)
//            }
//            .pickerStyle(.segmented)
//            .background(Color.red)
//            
//            Text("Value: \(favoriteColor)")
        }
        .frame( height: 250)
        .background(Color.gray)

    }
}

#Preview {
    KeyboardView()
}
