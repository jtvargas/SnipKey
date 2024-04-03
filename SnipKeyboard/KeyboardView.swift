//
//  KeyboardView.swift
//  SnipKeyboard
//
//  Created by Jonathan Taveras Vargas on 3/31/24.
//

import SwiftData
import SwiftUI

class KeyboardObserver: ObservableObject {
    @Published var isShowing = false
    @Published var height: CGFloat = 0
    
    func addObserver() {
        NotificationCenter.default.addObserver(
            self, selector: #selector(self.keyboardWillShow(_:)),
            name: UIResponder.keyboardWillShowNotification, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(self.keyboardWillHide(_:)),
            name: UIResponder.keyboardWillHideNotification, object: nil)
    }
    
    func removeObserver() {
        NotificationCenter.default.removeObserver(
            self, name: UIResponder.keyboardWillShowNotification, object: nil)
        NotificationCenter.default.removeObserver(
            self, name: UIResponder.keyboardWillHideNotification, object: nil)
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
    GridItem(.adaptive(minimum: 140, maximum: 200))
    //    GridItem(.adaptive(minimum: 80, maximum: 120)),
]

struct SnippetImageKeyboard: View {
    var body: some View {
        Image(systemName: "character.cursor.ibeam")
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
    @Query(sort: \SnippetItem.timestamp, order: .reverse) private var snippets: [SnippetItem]
    @Query() private var settings: [SettingsModel]
    let settingsViewModel = SettingsViewModel()
    @ObservedObject var keyboard: KeyboardObserver = KeyboardObserver()
    @State private var text: String = ""
    @State private var selectedFilter: Tags = .none
    //   TODO: Get this value from context, see settingsView to see how to inject the currentSettings model persisted
    @State private var currentSettings: SettingsModel = SettingsModel(afterPasteAction: .space)
    
    let columns = [GridItem(.adaptive(minimum: 150, maximum: 175), spacing: 6)]
    
    func actionPerform() {
        print("snippets: \(snippets)")
    }
    
    func getSnippetItems() -> [SnippetItem] {
        
        return [.dummy, .dummy, .dummy, .dummy, .dummy]
        //        if selectedFilter == .none {
        //            return snippets
        //        }
        //
        //        let snippetsFiltered = snippets.filter { snippetItem in
        //            return snippetItem.tag == selectedFilter
        //        }
        //
        //        return snippetsFiltered
    }
    
    private func emoji(_ value: Int) -> String {
        guard let scalar = UnicodeScalar(value) else { return "?" }
        return String(Character(scalar))
    }
    
    func actionKeyboardAfterPaste(actionKey: KeyboardAfterPasteAction) {
        switch actionKey {
        case .rtrn:
            // Unicode scalar value for 'Return' (Carriage Return)
            NotificationCenter.default.post(
                name: NSNotification.Name(rawValue: "addKey"), object: String(UnicodeScalar(0x000D)!))
            break
        case .changeReturn:
            NotificationCenter.default.post(
                name: NSNotification.Name(rawValue: "addKey"), object: String(UnicodeScalar(0x000D)!))
            NotificationCenter.default.post(
                name: NSNotification.Name(rawValue: "switchKey"), object: nil)
            break
        case .change:
            NotificationCenter.default.post(
                name: NSNotification.Name(rawValue: "addKey"), object: String(UnicodeScalar(0x0020)!))
            NotificationCenter.default.post(
                name: NSNotification.Name(rawValue: "switchKey"), object: nil)
            break
        case .space:
            NotificationCenter.default.post(
                name: NSNotification.Name(rawValue: "addKey"), object: String(UnicodeScalar(0x0020)!))
            break
        }
    }
    
    func sentValueToTextInput(value: String) {
        NotificationCenter.default.post(
            name: NSNotification.Name(rawValue: "addKey"), object: value)
        
        actionKeyboardAfterPaste(actionKey: currentSettings.afterPasteAction)
    }
    
    func deleteCharacter(){
        NotificationCenter.default.post(
            name: NSNotification.Name(rawValue: "deleteKey"), object: nil)
    }
    
    func getTitle() -> String{
        switch selectedFilter {
        case .none:
            return "All"
        default:
            return selectedFilter.displayText
        }
    }
    
    var body: some View {
        
        VStack {
            //            For multiple/custom tags use this style, or a toggle list button
            //            Menu {
            //                Picker(selection: $selectedFilter) {
            //                    ForEach(Tags.allCases, id: \.self) {
            //                        Text($0.displayText)
            //                    }
            //                    .pickerStyle(.menu)
            //                } label: {}
            //            } label: {
            //
            //                Label(getTitle(), systemImage: selectedFilter.imageTag)
            //                    .padding(.top, 10)
            //                    .padding(.horizontal)
            //                    .frame(maxWidth: .infinity, alignment: .leading)
            //                    .tint(Color.label)
            //                    .underline()
            //
            //            }
            
            ScrollView {
                //                Label(getTitle(), systemImage: selectedFilter.imageTag)
                //                    .padding(.top, 10)
                //                    .padding(.horizontal)
                //                    .frame(maxWidth: .infinity, alignment: .leading)
                //
                
                
                
                
                LazyVGrid(columns: layout, spacing: 20) {
                    ForEach(getSnippetItems(), id: \.self.id) { snippet in
                        Button {
                            sentValueToTextInput(value: snippet.content)
                        } label: {
                            SnippetListItem(item: snippet)
                                .padding(8)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 4)
                                        .stroke(Color.tertiarySystemBackground, lineWidth: 4)
                                )
                        }
                        
                    }
                }
                .padding()
                .frame(maxWidth: .infinity)
            }
            
            HStack (alignment: .center){
                Picker("", selection: $selectedFilter) {
                    Text("All").tag(Tags.none)
                    Text("Personal").tag(Tags.personal)
                    Text("Work").tag(Tags.work)
                    
                }
//                .padding(.bottom, 10)
//                .padding(.horizontal, 10)
                .pickerStyle(.segmented)
                
                    Button {
                        deleteCharacter()
                    } label: {
                        // Using a system image to represent the delete key
                        Image(systemName: "delete.left")
                            .resizable() // Make the image resizable
                              .aspectRatio(contentMode: .fit) // Keep the aspect ratio of the image
                              .frame(width: 20, height: 20) // Set the frame of the image to 35x35
                              .foregroundColor(.white) // Set the icon color to white
                              .padding(10) // Add padding around the image, adjust as needed
                              .background(Color.tertiaryLabel) // Use a red background to mimic the delete key
                              .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous)) // Clip the background to a circle shape
                              .shadow(radius: 5)
                    }
                  
                
            }
            .padding(.horizontal)
            .padding(.bottom, 10)
            
                
           
            
        }
        .frame(height: 260)
        .background(Color.secondarySystemBackground)
        .sensoryFeedback(.increase, trigger: selectedFilter)
        .onAppear(){
            settingsViewModel.modelContext = modelContext
            if let myCurrentSettings = settings.first {
                currentSettings = myCurrentSettings
            }
        }
        
    }
}

#Preview {
    KeyboardView()
}
