//
//  KeyboardView.swift
//  SnipKeyboard
//
//  Created by Jonathan Taveras Vargas on 3/31/24.
//

import SwiftData
import SwiftUI
import AlertToast

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

func firstFourteenCharacters(of inputString: String) -> String {
    if inputString.count >= 14 {
        let index = inputString.index(inputString.startIndex, offsetBy: 14)
        return String(inputString[..<index])
    } else {
        return inputString
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


struct VisualEffectViewKeyboard: UIViewRepresentable {
    var effect: UIVisualEffect?
    func makeUIView(context: UIViewRepresentableContext<Self>) -> UIVisualEffectView { UIVisualEffectView() }
    func updateUIView(_ uiView: UIVisualEffectView, context: UIViewRepresentableContext<Self>) { uiView.effect = effect }
}

struct KeyboardView: View {
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.modelContext) var modelContext
    @ObservedObject var keyboard: KeyboardObserver = KeyboardObserver()
    @Query(sort: \SnippetItem.creationDate, order: .reverse) private var snippets: [SnippetItem]
    @Query(sort: \SnipTag.name) private var tags: [SnipTag]
    @Query() private var settings: [SettingsModel]
  
    let columns = [GridItem(.adaptive(minimum: 150, maximum: 175), spacing: 6)]
    let deviceBiometrics: DeviceBiometrics = DeviceBiometrics()
    let settingsViewModel = SettingsViewModel()
    
    @State private var isUnlocked: Bool = false
    @State private var showCreateSnippetCTA = false
    @State private var showCreatedToast = false
    @State private var showToast = false
    @State private var currentSettings: SettingsModel = SettingsModel(afterPasteAction: .space)
    @State var snippetViewModel = SnippetViewModel()
    @State private var text: String = ""
    @State private var selectedFilter: SnipTag? = nil
    @State private var selectedText: String = ""
    

    var body: some View {
        ZStack {
            
      
        VisualEffectViewKeyboard(effect: UIBlurEffect(style: colorScheme == .dark ? .dark : .light))
                     .edgesIgnoringSafeArea(.all)
        VStack {
            //            For multiple/custom tags use this style, or a toggle list button
            HStack(alignment: .center) {
//                if selectedFilter != nil {
                    Label("\(selectedFilter?.name ?? "All")", systemImage: selectedFilter?.imageTag ?? "circle")
                        .tint(Color.label)
//                }
                EmptyView()
                Spacer()
                
                Label("Private Snippets: \(isUnlocked ? "Unlocked":"Locked")", systemImage: "\(isUnlocked ? "lock.open":"lock")")
                  
                Spacer()
                Button {
                    NotificationCenter.default.post(
                        name: NSNotification.Name(rawValue: "switchKey"), object: nil)
                } label: {
                    Label("Keyboard", systemImage: "keyboard.fill")
                        .underline()
                        .foregroundStyle(.blue.gradient)
                        .font(.custom("IBMPlexMono-Bold", size: 14))
                }
               
            }
            .font(.custom("IBMPlexMono-Medium", size: 14))
            .padding(.top, 4)
            .padding(.horizontal)
           
            
        
         
            ScrollView {
                if showCreateSnippetCTA {
                    floatingButton
                        .transition(.scale.combined(with: .opacity))
                        .animation(.easeInOut, value: showCreateSnippetCTA)
                }
              
                LazyVGrid(columns: layout, spacing: 20) {
                    ForEach(getSnippetItems(), id: \.self.id) { snippet in
                        Button {
                            sentValue(snippet: snippet)
                        } label: {
                            SnippetListItem(item: snippet)
                               
                                .lineLimit(1) // Limit text to a single line
                                .truncationMode(.tail)
                                .padding(8)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 4)
                                        .stroke(Color.tertiarySystemBackground, lineWidth: 4)
                                )
                        }
                        .shadow(color: .tertiaryLabel, radius: 1, x: 0, y: 0)
                        
                    }
                }
                .padding()
                .frame(maxWidth: .infinity)
            }
            
            if selectedFilter != nil {
                Button {
                    selectedFilter = nil
                } label: {
                    HStack {
                        Image(systemName: "minus.circle.fill")
                        Text("Remove Filter")
                            .font(.custom("IBMPlexMono-Medium", size: 12))
                    }.tint(Color.label).underline()
                    
                }
            }
            HStack(alignment: .center) {
                
                if !tags.isEmpty {
                    Picker("", selection: $selectedFilter) {
                        ForEach(tags, id: \.id) { tag in
                            HStack {
                                Image(systemName: tag.imageTag!)
                            }
                            .tag(Optional(tag))
                        }
                        
                    }
                    .pickerStyle(.segmented)
                }
                
                
                Button {
                    deleteCharacter()
                } label: {
                    // Using a system image to represent the delete key
                    Image(systemName: "delete.left")
                        .resizable()  // Make the image resizable
                        .aspectRatio(contentMode: .fit)  // Keep the aspect ratio of the image
                        .frame(width: 20, height: 20)  // Set the frame of the image to 35x35
                        .foregroundColor(.white)  // Set the icon color to white
                        .padding(10)  // Add padding around the image, adjust as needed
                        .background(Color.tertiaryLabel)  // Use a red background to mimic the delete key
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))  // Clip the background to a circle shape
                        .shadow(radius: 5)
                }
               
               
                
            }
            .padding(.horizontal)
            .padding(.bottom, 10)
            
           
        }
        }
        .frame(width: .infinity, height: 260)
        .background(Color.tertiaryLabel)
        .sensoryFeedback(.increase, trigger: selectedFilter)
        .onAppear {
            settingsViewModel.modelContext = modelContext
            snippetViewModel.modelContext = modelContext

            if let myCurrentSettings = settings.first {
                currentSettings = myCurrentSettings
            }
            
//            setupSelectTextObserver()
            
        }
        .toast(isPresenting: $showToast) {
            AlertToast(
                displayMode: .banner(
                    .pop
                ),
                type: .systemImage(
                    "doc.on.clipboard",
                    .label
                ),
                title: !checkFullAccess() ? "Enable full keyboard access to copy/paste images." : "Image copied to your clipboard. Paste to use it.",
                style: .style(
                    backgroundColor: Color.tertiarySystemBackground,
                    titleFont: .custom(
                        "IBMPlexMono-Medium",
                        size: 14
                    )
                )
            )
        }
        .toast(isPresenting: $showCreatedToast) {
            AlertToast(
                displayMode: .banner(
                    .pop
                ),
                type: .systemImage(
                    "checkmark.circle.fill",
                    .label
                ),
                title: "New Snippet created!",
                style: .style(
                    backgroundColor: Color.tertiarySystemBackground,
                    titleFont: .custom(
                        "IBMPlexMono-Medium",
                        size: 14
                    )
                )
            )
            
        }
        
    }
    
    private var floatingButton: some View {
           Button(action: {
               createNewSnippetFromKeyboard(content: selectedText)
           }) {
               VStack{
                   Text("Create New Snippet")
                       .foregroundColor(.white)
                       .padding()
                       .frame(width: 220, height: 50)
                       .background(Color.blue)
                       .cornerRadius(25)
                       .shadow(radius: 10)
                       .font(.custom("IBMPlexMono-Medium", size: 16))
                   Text("(with value selected)")
                       .font(.custom("IBMPlexMono-Medium", size: 10))
               }
             
              
           }
           .fixedSize()
           .padding(.top)
       }
    
    func actionPerform() {
        print("snippets: \(snippets)")
    }
    
    func getSnippetItems() -> [SnippetItem] {
        if selectedFilter == nil {
            return snippets
        }
        
        let snippetsFiltered = snippets.filter { snippetItem in
            return snippetItem.customTag == selectedFilter
        }
        
        return snippetsFiltered
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
    
    func sentValue(snippet: SnippetItem){
        if snippet.isSecure {
            sentSecureValue(snippet: snippet)
        }else {
            sentValueToKeyboard(snippet: snippet)
        }
    }
    
   
    
    func sentSecureValue(snippet: SnippetItem) {
        deviceBiometrics.authenticate(successHandler: {
            isUnlocked = true
            
            sentValueToKeyboard(snippet: snippet)
        }, unSuccessHandler: { error in
            isUnlocked = false
            print("Can't access")
            
        })
    }
    
    func sentValueToKeyboard(snippet: SnippetItem) {
        NotificationCenter.default.post(
            name: NSNotification.Name(rawValue: "addKey"), object: snippet)
        
        if snippet.type == .image{
            showToast.toggle()
        } else {
            actionKeyboardAfterPaste(actionKey: currentSettings.afterPasteAction)
        }
        
       
    }
    
    func deleteCharacter() {
        NotificationCenter.default.post(
            name: NSNotification.Name(rawValue: "deleteKey"), object: nil)
    }
    
    
    //    TODO: For some reason manipulating swiftdata from keyboard/extension the DB is not updating correctly
    func createNewSnippetFromKeyboard(content: String) {
        let title = firstFourteenCharacters(of: content)
        let content = content
        
        snippetViewModel.createSnippet(title, content: content, type: .txt, isSecure: false)
        showCreatedToast.toggle()
    }
    
    

    func setupSelectTextObserver() {
        NotificationCenter.default.addObserver(forName: NSNotification.Name(rawValue: "selectText"), object: nil, queue: nil){ notification in
           
            
            if let text = notification.object as? String {
                
                if !text.isEmpty {
                    showCreateSnippetCTA = true
                    selectedText = text
                    print("TEXT VALUE: \(text)")
                }
               
            }
         
        }
        
        NotificationCenter.default.addObserver(forName: NSNotification.Name(rawValue: "selectTextEmpty"), object: nil, queue: nil){ notification in
           
            showCreateSnippetCTA = false
         
        }
    }
}

#Preview {
    let container = SnipKeyDataManager().makeSharedContainer()
    
    return KeyboardView()
        .modelContainer(container)
}
