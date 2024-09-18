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

enum SortOption: String, CaseIterable {
    case dateCreated = "Date Created"
    case recentlyUsed = "Recently Used"
    case alphabetical = "Albabetical"
    
    var imageName: String {
        switch self {
        case .dateCreated:
            return "calendar.circle"
        case .recentlyUsed:
            return "timer.circle"
        case .alphabetical:
            return "textformat.abc"
        }
    }
}

struct KeyboardView: View {
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.modelContext) var modelContext
    @AppStorage("sortBySelection") var sortBySelection: SortOption = .dateCreated
    
    @Environment(SettingsViewModel.self) private var settingsViewModel
    @ObservedObject var keyboard: KeyboardObserver = KeyboardObserver()
    @Query(sort: \SnippetItem.creationDate, order: .reverse) private var snippets: [SnippetItem]
    @Query(sort: \SnipTag.name) private var tags: [SnipTag]
    @Query() private var settings: [SettingsModel]
    
    let columns = [GridItem(.adaptive(minimum: 150, maximum: 175), spacing: 6)]
    let deviceBiometrics: DeviceBiometrics = DeviceBiometrics()
//    let settingsViewModel = SettingsViewModel()
    
    @State private var isUnlocked: Bool = false
    @State private var hasFullAccess: Bool = false
    @State private var showCreateSnippetCTA = false
    @State private var showCreatedToast = false
    @State var snippetsTest: [SnippetItem] = []
    @State private var showToast = false
    @State var snippetViewModel = SnippetViewModel()
    @State private var text: String = ""
    @State private var selectedFilter: SnipTag? = nil
    @State private var selectedText: String = ""
    
//    delete functionality
    @State private var isLongPressing = false
     @State private var deleteTimer: Timer?
    
    // sort functionality
    @State private var sortOption: SortOption = .alphabetical
    @State private var sortOrder: SortOrder = .forward
        
    var currentKeyboardSettings: SettingsModel {
        if let myCurrentSettings = settings.first {
            return myCurrentSettings
        }
        
        return SettingsModel(afterPasteAction: .space)
    }
    
    
    var body: some View {
        ZStack {
            
            
            VisualEffectViewKeyboard(effect: UIBlurEffect(style: colorScheme == .dark ? .dark : .light))
//                .edgesIgnoringSafeArea(.all)
            VStack {
                //            For multiple/custom tags use this style, or a toggle list button
                HStack(alignment: .center) {
//                    Label("\(selectedFilter?.name ?? "All")", systemImage: selectedFilter?.imageTag ?? "circle")
//                        .tint(Color.label)
                    
                    
                    Menu {
                        Picker("Sort by", selection: $sortOption) {
                            ForEach(SortOption.allCases, id: \.self) { option in
                                HStack {
                                    Text(option.rawValue)
                                    Spacer()
                                    Image(systemName: option.imageName)
                                }
                                .tag(option)
                            }
                        }
                        
                        Picker("Order", selection: $sortOrder) {
                            switch sortOption {
                            case .dateCreated:
                                Label("Earliest First", systemImage: "arrow.up")
                                    .tag(SortOrder.forward)
                                Label("Latest First", systemImage: "arrow.down")
                                    .tag(SortOrder.reverse)
                            case .recentlyUsed:
                                Label("Most Recent First", systemImage: "arrow.up")
                                    .tag(SortOrder.reverse)
                                Label("Least Recent First", systemImage: "arrow.down")
                                    .tag(SortOrder.forward)
                            case .alphabetical:
                                Label("A to Z", systemImage: "arrow.up")
                                    .tag(SortOrder.forward)
                                Label("Z to A", systemImage: "arrow.down")
                                    .tag(SortOrder.reverse)
                            }
                        }
                    } label: {
                        Label("Sort", systemImage: "arrow.up.arrow.down")
                            .foregroundStyle(.blue.gradient)
                    }
                    EmptyView()
                    Spacer()
                    
                    Label("\(isUnlocked ? "Snippets Unlocked" : "Snippets Locked")", systemImage: "\(isUnlocked ? "lock.open" : "lock")")
                        .foregroundStyle(.white.gradient)
                    
                    
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
                        if checkFullAccess() {
                            floatingButton
                                .transition(.scale.combined(with: .opacity))
                                .animation(.easeInOut, value: showCreateSnippetCTA)
                        } else {
                            Text("Enable full access to quickly create snippets from selected text.")
                                .foregroundColor(.secondary)
                                .font(.custom("IBMPlexMono-Regular", size: 12))
                                .padding(.top)
                            
                            
                        }
                       
                    }
                    
                    LazyVGrid(columns: layout, spacing: 20) {
                        ForEach(getSnippets(), id: \.self.id) { snippet in
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
                        MenuTags()
                    }else {
                        Text("Add tags for quick snippet search.")
                            .foregroundColor(.secondary)
                            .font(.custom("IBMPlexMono-Regular", size: 12))
                        
                        Spacer()
                    }
                    
                    Button {
                        spaceAction()
                    } label: {
                        // Using a system image to represent the delete key
                        Image(systemName: "space")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 52, height: 20)
                            .foregroundColor(.white)
                            .padding(10)
                            .background(Color.tertiaryLabel)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .shadow(radius: 5)
                    }
                    Button {
                        returnAction()
                    } label: {
                        // Using a system image to represent the delete key
                        Image(systemName: "return")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 30, height: 20)
                            .foregroundColor(.white)
                            .padding(10)
                            .background(Color.tertiaryLabel)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .shadow(radius: 5)
                    }
                    
                    
                    Button {
                        // Single tap action
                                    deleteCharacter(isLongPress: false)
                    } label: {
                        // Using a system image to represent the delete key
                        Image(systemName: "delete.left")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 20, height: 20)
                            .foregroundColor(.white)
                            .padding(10)
                            .background(Color.tertiaryLabel)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .shadow(radius: 5)
                    }
                    .simultaneousGesture(
                               LongPressGesture(minimumDuration: 0.5)
                                   .onEnded { _ in
                                       isLongPressing = true
                                       deleteCharacter(isLongPress: true)
                                       startRapidDeletion()
                                   }
                           )
                           .simultaneousGesture(
                               DragGesture(minimumDistance: 0)
                                   .onEnded { _ in
                                       if isLongPressing {
                                           isLongPressing = false
                                           stopRapidDeletion()
                                       }
                                   }
                           )
                    
                    
                    
                }
                .padding(.horizontal)
                .padding(.bottom, 10)
                
                
            }
        }
        .frame(height: 260)
        .background(Color.tertiaryLabel)
        .sensoryFeedback(.increase, trigger: selectedFilter)
        .onAppear {
            settingsViewModel.modelContext = modelContext
            snippetViewModel.modelContext = modelContext
            
            setupSelectTextObserver()
            
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
                title: !checkFullAccess() ? "Enable full keyboard access to copy/paste images." : "File copied to your clipboard. Paste to use it.",
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
    
    @ViewBuilder
    func MenuTags() -> some View {
        Menu {
            ForEach(tags, id: \.id) { tag in
                Button(action: {
                    selectedFilter = tag
                }) {
                    HStack {
                        Image(systemName: tag.imageTag!)
                        Text(tag.name ?? "") // Assuming tag has a 'name' property
                        if tag == selectedFilter {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack {
                Image(systemName: selectedFilter?.imageTag ?? "line.3.horizontal.decrease.circle")
                Text(selectedFilter?.name ?? "Filter")
                    .foregroundStyle(.blue.gradient)
                Image(systemName: "chevron.up")
                    .foregroundStyle(.blue.gradient)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(8)
           
        }
      
    }
    
    private func getSnippets() -> [SnippetItem] {
        // Filter snippets
        let filteredSnippets = selectedFilter.map { filter in
            snippets.filter { $0.customTag == filter }
        } ?? snippets
        
        // Sort snippets
        return filteredSnippets.sorted { first, second in
            switch sortOption {
            case .dateCreated:
                let firstDate = first.creationDate ?? .distantPast
                let secondDate = second.creationDate ?? .distantPast
                return sortOrder == .forward ? firstDate < secondDate : firstDate > secondDate
                
            case .recentlyUsed:
                let firstDate = first.lastTimeUsed ?? .distantPast
                let secondDate = second.lastTimeUsed ?? .distantPast
                return sortOrder == .forward ? firstDate < secondDate : firstDate > secondDate
                
            case .alphabetical:
                let firstTitle = first.title?.lowercased() ?? ""
                let secondTitle = second.title?.lowercased() ?? ""
                return sortOrder == .forward ? firstTitle < secondTitle : firstTitle > secondTitle
            }
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
            .fixedSize()
            .padding(.top)
            
        }
    }
    
    func actionPerform() {
        print("snippets: \(snippets)")
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
            NotificationCenter.default.post(
                name: NSNotification.Name(rawValue: "addKey"), object: String(UnicodeScalar(0x000D)!))
            break
        case .changeReturn:
            NotificationCenter.default.post(
                name: NSNotification.Name(rawValue: "addKey"), object: String(UnicodeScalar(0x000D)!))
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
        case .nothing:
            break
        }
    }
    
    func sentValue(snippet: SnippetItem){
        snippetViewModel.trackSnippetUsage(snippet: snippet)
        
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

        if snippet.type == .image || snippet.type == .file {
            showToast = true
        } else {
            actionKeyboardAfterPaste(actionKey: currentKeyboardSettings.afterPasteAction)
        }
        
       
    }
    
    
    
    func deleteCharacter(isLongPress: Bool) {
        NotificationCenter.default.post(
            name: NSNotification.Name(rawValue: "deleteKey"),
            object: isLongPress
        )
    }
    
    func spaceAction() {
        NotificationCenter.default.post(
            name: NSNotification.Name(rawValue: "addKey"), object: String(UnicodeScalar(0x0020)!))
    }
    
    func returnAction() {
        NotificationCenter.default.post(
            name: NSNotification.Name(rawValue: "addKey"), object: String(UnicodeScalar(0x000D)!))
    }
    
    func startRapidDeletion() {
        deleteTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            deleteCharacter(isLongPress: true)
        }
    }
    
    func stopRapidDeletion() {
        deleteTimer?.invalidate()
        deleteTimer = nil
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
        
        NotificationCenter.default.addObserver(forName: NSNotification.Name(rawValue: "hasFullAccess"), object: nil, queue: nil){ notification in
            
            if let fullAccess = notification.object as? Bool {
                
                hasFullAccess = fullAccess
                
            }
            
        }
    }
}

struct KeyboardViewExt: View {
    let container = SnipKeyDataManager().makeSharedContainer()
    @State private var settingsViewModel: SettingsViewModel?
    
    var body: some View {
        Group {
            if let settingsViewModel = settingsViewModel {
                KeyboardView()
                    .modelContainer(container)
                    .environment(settingsViewModel)
            } else {
                ProgressView()
                    .onAppear {
                        Task {
                            await loadSettingsViewModel()
                        }
                    }
            }
        }
    }
    
    private func loadSettingsViewModel() async {
        let modelContext = await container.mainContext
        let viewModel = SettingsViewModel(modelContext: modelContext)
        settingsViewModel = viewModel
    }
}
#Preview {
    let tempSettingsContainer = SnipKeyDataManager().makeSharedContainer()
    let settingsViewModel = SettingsViewModel(modelContext: tempSettingsContainer.mainContext)
    @State var isPresentingSettings: Bool = false
    
    return KeyboardViewExt()
        .onAppear {
            settingsViewModel.modelContext = tempSettingsContainer.mainContext
            settingsViewModel.setupKeyboardSettings()
        }
        .modelContainer(tempSettingsContainer)
        .environment(settingsViewModel)
}
