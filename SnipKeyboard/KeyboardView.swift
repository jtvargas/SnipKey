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
    GridItem(.adaptive(minimum: 135, maximum: 200))
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
    case alphabetical = "Albabetical"
    case dateCreated = "Date Created"
    case recentlyUsed = "Recently Used"
  
    
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
    
    // Optional: QWERTY state from environment (nil if running without QWERTY support)
    @Environment(QWERTYKeyboardState.self) private var qwertyStateFromEnvironment: QWERTYKeyboardState?
    @ObservedObject var keyboard: KeyboardObserver = KeyboardObserver()
    @Query(sort: \SnippetItem.creationDate, order: .reverse) private var snippets: [SnippetItem]
    @Query(sort: \SnipTag.name) private var tags: [SnipTag]
    @Query() private var settings: [SettingsModel]
    
    let columns = [GridItem(.adaptive(minimum: 135, maximum: 175), spacing: 6)]
    let deviceBiometrics: DeviceBiometrics = DeviceBiometrics()
//    let settingsViewModel = SettingsViewModel()
    
    @State private var isUnlocked: Bool = false
    @State private var hasFullAccess: Bool = false
    @State private var showCreateSnippetCTA = false
    @State private var showCreatedToast = false
    @State var snippetsTest: [SnippetItem] = [SnippetItem.dummy]
    @State private var showToast = false
    @State var snippetViewModel = SnippetViewModel()
    @State private var text: String = ""
    @State private var selectedFilter: SnipTag? = nil
    @State private var selectedText: String = ""
    
//    delete functionality
    @State private var isLongPressing = false
     @State private var deleteTimer: Timer?
    
    // sort functionality
    @State private var sortOption: SortOption = .recentlyUsed
    @State private var sortOrder: SortOrder =  .forward
        
    var currentKeyboardSettings: SettingsModel {
        if let myCurrentSettings = settings.first {
            return myCurrentSettings
        }
        
        return SettingsModel(afterPasteAction: .space)
    }
    
    var hasSecureSnippets: Bool {
        return snippets.contains { $0.isSecure }
    }
    
    
    var body: some View {
        ZStack {
            
//            VisualEffectViewKeyboard(effect: UIBlurEffect(style: colorScheme == .dark ? .dark : .light))
            Color.clear
                .edgesIgnoringSafeArea(.all)
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
                    
                    if hasSecureSnippets {
                        Label("\(isUnlocked ? "Vault Open" : "Vault Locked")", systemImage: "\(isUnlocked ? "lock.open" : "lock")")
                            .foregroundStyle(Color.secondaryLabel)
                    }
                   
                    
                    
                    Spacer()
                    // Toggle back to QWERTY keyboard mode
                    if let qState = qwertyStateFromEnvironment {
                        Button {
                            qState.showingSnippets = false
                        } label: {
                            Label("Keyboard", systemImage: "keyboard.fill")
                                .underline()
                                .foregroundStyle(.blue.gradient)
                                .font(.custom("IBMPlexMono-Bold", size: 14))
                        }
                    } else {
                        // Fallback: switch to next keyboard (pre-QWERTY behavior)
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
                            Text("Enable Full Access to quickly create snippets from selected text.")
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
                                SnippetListItemMinimal(item: snippet)
                                    .truncationMode(.tail)
                            }
                            
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
                    
                   
                    ButtonActionsView()
                   
                    
                }
                .padding(.horizontal)
                .padding(.bottom, 10)
                
                
            }
        }
        .frame(height: KeyboardDimensions.totalHeight(forScreenWidth: UIScreen.main.bounds.width))
//        .background(Color.clear)
        .sensoryFeedback(.increase, trigger: selectedFilter)
        .onAppear {
            settingsViewModel.modelContext = modelContext
            snippetViewModel.modelContext = modelContext
            
            setupSelectTextObserver()
            
        }
        .onDisappear {
            removeSelectTextObservers()
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
    func ButtonActionsView() -> some View {
        Button {
            spaceAction()
        } label: {
            Image(systemName: "space")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 52, height: 20)
                .foregroundStyle(.blue.gradient)
                .padding(10)
                .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
        }
        .glassEffect()
        
        Button {
            returnAction()
        } label: {
            Image(systemName: "return")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 30, height: 20)
                .foregroundStyle(.blue.gradient)
                .padding(10)
        }
        .glassEffect()
        
        Button {
            deleteCharacter(isLongPress: false)
        } label: {
            Image(systemName: "delete.left")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 20, height: 20)
                .foregroundStyle(.blue.gradient)
                .padding(10)
        }
        .glassEffect()
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
    
    @ViewBuilder
    func MenuTags() -> some View {
        Menu {
            ForEach(tags, id: \.id) { tag in
                Button(action: {
                    selectedFilter = tag
                }) {
                    Label {
                        HStack {
                            Text(tag.name ?? "")
                            if tag == selectedFilter {
                                Image(systemName: "checkmark")
                            }
                        }
                    } icon: {
                        HStack(spacing: 2) {
                            if let colorHex = tag.colorHex, let color = Color(hex: colorHex) {
                                Image(systemName: "circle.fill")
                                    .foregroundColor(color)
                                    .font(.system(size: 8))
                            }
                            Image(systemName: tag.imageTag!)
                        }
                    }
                }
            }
        } label: {
            HStack {
                if let filter = selectedFilter, let colorHex = filter.colorHex {
                    TagColorIndicator(colorHex: colorHex, size: 8)
                }
                Image(systemName: selectedFilter?.imageTag ?? "line.3.horizontal.decrease.circle")
                Text(selectedFilter?.name ?? "Filter")
                    .foregroundStyle(.blue.gradient)
                Image(systemName: "chevron.up")
                    .foregroundStyle(.blue.gradient)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
//            .background(Color.secondary.opacity(0.1))
//            .cornerRadius(8)
           
        }
        .glassEffect()
      
    }
    
    private func getSnippets() -> [SnippetItem] {
        // Filter snippets based on selectedFilter
            let filteredSnippets: [SnippetItem]
            if let filter = selectedFilter {
                filteredSnippets = snippets.filter { $0.customTag == filter }
            } else {
                filteredSnippets = snippets
            }
        
        // Sort snippets
        return filteredSnippets.sorted { first, second in
            switch sortOption {
            case .dateCreated:
                let firstDate = first.creationDate ?? .distantPast
                let secondDate = second.creationDate ?? .distantPast
                // Most recent first when forward, oldest first when reverse
                return sortOrder == .forward ? firstDate > secondDate : firstDate < secondDate
                
            case .recentlyUsed:
                let firstDate = first.lastTimeUsed ?? .distantPast
                let secondDate = second.lastTimeUsed ?? .distantPast
                // Most recent first when forward, oldest first when reverse
                return sortOrder == .forward ? firstDate > secondDate : firstDate < secondDate
                
            case .alphabetical:
                let firstTitle = first.title?.lowercased() ?? ""
                let secondTitle = second.title?.lowercased() ?? ""
                // A-Z when forward, Z-A when reverse
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
    
//    to be able to send a notification to keyboard and verify if has full access and set on variable key
    func keyboardAppearCheck() {
        print("keyboard appear")
        NotificationCenter.default.post(
            name: NSNotification.Name(rawValue: "onAppearKeyboard"), object: String(UnicodeScalar(0x0020)!))
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
    
    
    
    /// Stored observer tokens so we can remove them in onDisappear.
    /// Without cleanup, each appearance of the snippet view would accumulate
    /// duplicate observers — causing N handler calls per notification after N toggles.
    @State private var notificationObservers: [Any] = []
    
    func setupSelectTextObserver() {
        // Remove any existing observers first (safety net for rapid toggle)
        removeSelectTextObservers()
        
        let o1 = NotificationCenter.default.addObserver(forName: NSNotification.Name(rawValue: "selectText"), object: nil, queue: nil){ notification in
            
            if let text = notification.object as? String {
                
                if !text.isEmpty {
                    showCreateSnippetCTA = true
                    selectedText = text
                }
                
            }
            
        }
        
        let o2 = NotificationCenter.default.addObserver(forName: NSNotification.Name(rawValue: "selectTextEmpty"), object: nil, queue: nil){ notification in
            
            showCreateSnippetCTA = false
            
        }
        
        let o3 = NotificationCenter.default.addObserver(forName: NSNotification.Name(rawValue: "hasFullAccess"), object: nil, queue: nil){ notification in
            
            if let fullAccess = notification.object as? Bool {
                hasFullAccess = fullAccess
                
            }
            
        }
        
        notificationObservers = [o1, o2, o3]
    }
    
    func removeSelectTextObservers() {
        for observer in notificationObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        notificationObservers.removeAll()
    }
}

// Custom button style for liquid press effect
struct LiquidButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1.0)
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

struct KeyboardViewExt: View {
    let container = SnipKeyDataManager().makeSharedContainer()
    @State private var settingsViewModel: SettingsViewModel?

    // QWERTY keyboard state and actions, passed from KeyboardViewController
    var qwertyState: QWERTYKeyboardState
    var keyboardActions: KeyboardActions
    
    var body: some View {
        Group {
            if let settingsViewModel = settingsViewModel {
                Group {
                    if qwertyState.showingSnippets {
                        // Existing snippet grid view
                        KeyboardView()
                    } else {
                        // New QWERTY keyboard view
                        QWERTYKeyboardView()
                    }
                }
                .modelContainer(container)
                .environment(settingsViewModel)
                .environment(qwertyState)
                .environment(\.keyboardActions, keyboardActions)
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
    
    return KeyboardViewExt(
        qwertyState: QWERTYKeyboardState(),
        keyboardActions: KeyboardActions.noop
    )
    .onAppear {
        settingsViewModel.modelContext = tempSettingsContainer.mainContext
        settingsViewModel.setupKeyboardSettings()
    }
    .modelContainer(tempSettingsContainer)
    .environment(settingsViewModel)
}
