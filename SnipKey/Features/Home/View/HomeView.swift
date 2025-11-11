//
//  SnippetHomeView.swift
//  SnipKey
//
//  Created by Jonathan Taveras Vargas on 5/9/24.
//

import SwiftUI
import SwiftData
import StoreKit
import CloudKitSyncMonitor
import UniformTypeIdentifiers
import AlertToast

struct HomeView: View {
    @AppStorage("showTipDev") var showTipDev: Bool = false
    @AppStorage("isRequestedRating") var isRequestedRating: Bool = false
    @AppStorage("isKeyboardShortcutEnabled") var isKeyboardShortcutEnabled: Bool = false

    @available(iOS 14.0, *)
    @ObservedObject var syncMonitor = SyncMonitor.shared
    
    
    @Environment(\.requestReview) var requestReview
    @Environment(\.modelContext) var modelContext
    @Environment(\.scenePhase) var scenePhase
    
    private let createSnippetTip = CreateSnippetTip()
    private let iCloudTip = CloudIndicatorTip()
    
    
    @Namespace private var namespaceLeft
    @Namespace private var namespaceRight
    
    @State var viewModel = SnippetViewModel()
    @State  var selectedSnippet: SnippetItem? = nil
    @State private var columnVisibility =
    NavigationSplitViewVisibility.all
    @State private var selectedFilter: SnipTag? = nil
    @State var isPresentedWelcomeInfo: Bool = false
    @State var isPresentedFormModal: Bool = false
    @State var isPresentingSettings: Bool = false
    @State var isKeyboardActive: Bool = false
    @State var isPresentedGuide: Bool = false
    @State var isPresentingSnippetFiles: Bool = false
    @State private var showToast = false
    
    @Query(sort: \SnippetItem.creationDate, order: .reverse, animation: .bouncy) private var snippets:
    [SnippetItem]
    @Query(sort: \SnipTag.creationDate) private var tags: [SnipTag]
    @Query(sort: \SnippetFile.id, order: .reverse, animation: .bouncy) private var files:
    [SnippetFile]
    
    @State private var hasFullAccess = false
    
    func checkFullAccessKy() {
        // Attempt to access shared UserDefaults from App Group
        if let userDefaults = UserDefaults(suiteName: "group.snipkey") {
            // Try to read a known value (written by the extension)
            if userDefaults.bool(forKey: "fullAccessGranted") {
                hasFullAccess = true
            } else {
                hasFullAccess = false
            }
        }
    }
    
    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility){
            VStack  {
                if !snippets.isEmpty {
                    Group {
                        KeyboardStatusView(
                            isShortcutsActive: isKeyboardShortcutEnabled,
                            onKeyboardStatusPress: handleOnKeyboardStatusPress
                        )
                        .pressable()
                    }
                    .padding(.horizontal)
                    .padding(.top)
                    .sheet(
                        isPresented: $isPresentedGuide,
                        content: {
                            KeyboardHelpGuideView(isPresented: $isPresentedGuide)
                        })
                }
                
                ZStack(alignment:.bottom) {
                    Form {
                        
                        Section(
                            header: HStack {
                                Text(snippets.isEmpty ? "SnipKey" : "Snippets")
                                Spacer()
                                
                                if selectedFilter != nil {
                                    Button {
                                        selectedFilter = nil
                                    } label: {
                                        HStack {
                                            Image(systemName: "minus.circle.fill")
                                            Text("Remove Filter")
                                                .font(.custom("IBMPlexMono-Medium", size: 14))
                                        }
                                        
                                    }
                                }
                                
                            }
                        ) {
                            List {
                                ForEach(getSnippetItems(), id: \.self) { snippetItem in
                                    NavigationLink(destination: SnippetViewDetail(item: snippetItem)) {
                                        SnippetListItem(item: snippetItem)
                                    }
                                    .swipeActions(edge: .leading) {
                                        Button {
                                            let clipboard = UIPasteboard.general
                                            clipboard.setValue(snippetItem.content!, forPasteboardType: UTType.plainText.identifier)
                                            showToast.toggle()
                                        } label: {
                                            Label("Copy", systemImage: "doc.on.doc.fill")
                                        }
                                        .tint(Color.quaternaryLabel)
                                    }
                                    
                                    
                                }
                                .onDelete(perform: { indexSet in
                                    self.handleDeleteSnippet(offsets: indexSet)
                                })
                            }
                        }
                    }
                    .safeAreaPadding(EdgeInsets(top: 0, leading: 0, bottom: 170, trailing: 0))
                    
                    Group {
                        gradient2
                            .allowsHitTesting(false)
                        HStack(alignment: .bottom) {
                            Button {
                                self.isPresentedWelcomeInfo.toggle()
                            } label: {
                                Image(systemName: "info.circle.fill")
                                    .font(.system(size:36, weight: .heavy))
                                    .foregroundStyle(Color.label.gradient)
                            }
                            .pressable()
                            .sheet(isPresented: $isPresentedWelcomeInfo) {
                                OnboardingView(appName: "SnipKey", showOnboarding: $isPresentedWelcomeInfo, features: [
                                    Feature(title: "Create & Use Snippets", description: "Craft snippets, use them anywhere.", icon: "doc.on.doc.fill"),
                                    Feature(title: "Keyboard Extension", description: "Access snippets directly from keyboard.", icon: "keyboard.fill"),
                                    Feature(title: "Organize with Tags", description: "Sort snippets using quick tags.", icon: "tag.fill"),
                                    Feature(title: "Secure Data", description: "Encrypt sensitive snippets.", icon: "lock.fill"),
                                    Feature(title: "iCloud Sync", description: "Access across all your devices.", icon: "cloud.fill"),
                                ], color: Color.label)
                            }
                            
//                            Spacer()
//                            Button {
//                                self.isPresentedFormModal.toggle()
//                            } label: {
//                                Image(systemName: "plus.square.fill")
//                                    .foregroundStyle(Color.label.gradient)
//                                    .font(.system(size: 62))
//                                
//                            }
//                            .pressable()
//                            .popoverTip(createSnippetTip)
//                            .sheet(isPresented: $isPresentedFormModal) {
//                                NavigationStack {
//                                    SnippetForm(snippet: nil, isFormVisible: $isPresentedFormModal)
//                                }
//                                .presentationBackground(Color.clear)
//                            }
//                            Spacer()
//                            Button {
//                                self.isPresentingSettings.toggle()
//                            } label: {
//                                Image(systemName: "gearshape.circle.fill")
//                                    .font(.system(size:36, weight: .heavy))
//                                    .foregroundStyle(Color.label.gradient)
//                            }
//                            .pressable()
//                            .sheet(isPresented: $isPresentingSettings) {
//                                SettingsView(isPresentingSettings: $isPresentingSettings)
//                                
//                            }
                            
                        }
                        .padding()
                        .padding(.bottom, 30)
                    }
                    
                }
            }
            .ignoresSafeArea(.all, edges: .bottom)
            .navigationTitle(snippets.isEmpty ? "" : "SnipKey")
            .font(.custom("IBMPlexMono-Medium", size: 16))
            .tint(Color.label)
            .navigationBarTitleDisplayMode(.inline)
            .overlay {
                if snippets.isEmpty {
                    SnippetListEmpty()
                        .frame(width: .infinity, height: 100) // Adjust these dimensions as needed
                        .background(Color.clear)
                }
            }
            .toolbar {
                ToolbarItem(placement: .bottomBar) {
//                    GlassEffectContainer(spacing: 40.0) {
                        HStack(spacing: 10.0) {
                            GlassEffectContainer(spacing: 10.0) {
                                HStack(spacing: 10.0){
                                    Button {
                                        self.isPresentedWelcomeInfo.toggle()
                                    } label: {
                                        Image(systemName: "info.circle.fill")
                                            .font(.system(size:36, weight: .heavy))
                                            .foregroundStyle(Color.label.gradient)
                                    }
                                    .pressable()
                                    .sheet(isPresented: $isPresentedWelcomeInfo) {
                                        OnboardingView(appName: "SnipKey", showOnboarding: $isPresentedWelcomeInfo, features: [
                                            Feature(title: "Create & Use Snippets", description: "Craft snippets, use them anywhere.", icon: "doc.on.doc.fill"),
                                            Feature(title: "Keyboard Extension", description: "Access snippets directly from keyboard.", icon: "keyboard.fill"),
                                            Feature(title: "Organize with Tags", description: "Sort snippets using quick tags.", icon: "tag.fill"),
                                            Feature(title: "Secure Data", description: "Encrypt sensitive snippets.", icon: "lock.fill"),
                                            Feature(title: "iCloud Sync", description: "Access across all your devices.", icon: "cloud.fill"),
                                        ], color: Color.label)
                                    }

                                    Button {
                                        self.isPresentingSettings.toggle()
                                    } label: {
                                        Image(systemName: "gearshape.circle.fill")
                                            .font(.system(size:36, weight: .heavy))
                                            .foregroundStyle(Color.label.gradient)
                                    }
                                    .pressable()
                                    .sheet(isPresented: $isPresentingSettings) {
                                        SettingsView(isPresentingSettings: $isPresentingSettings)
                                        
                                    }
                                }
                                .glassEffect()
                                .glassEffectUnion(id: "settings", namespace: namespaceLeft)
                                .buttonStyle(.glass)
                                
                               
                            }
                            
                            
                            Spacer()
                            Button {
                                self.isPresentedFormModal.toggle()
                            } label: {
                                Image(systemName: "plus.circle.fill")
                                    .foregroundStyle(Color.label.gradient)
                                    .font(.system(size: 46))
                                
                            }
                            .popoverTip(createSnippetTip)
                            .sheet(isPresented: $isPresentedFormModal) {
                                NavigationStack {
                                    SnippetForm(snippet: nil, isFormVisible: $isPresentedFormModal)
                                }
                                .presentationBackground(Color.clear)
                            }
                            .glassEffect()
                            .glassEffectUnion(id: "create", namespace: namespaceLeft)
                         
                     
                      
                        }
//                    }
                    
                 
                    
//                    .buttonStyle(.glass)
                }
                    .sharedBackgroundVisibility(.hidden)
                
                
                ToolbarItem(placement: .topBarLeading) {
                    if !snippets.isEmpty {
                        EditButton()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .underline()
                            .tint(Color.label)
                            .bold()
                            .font(.custom("IBMPlexMono-Medium", size: 16))
                        
                    }
                }
                
                Group {
                    ToolbarItem(placement: .topBarLeading) {
                        if #available(iOS 14.0, *) {
                            Button {
                                CloudIndicatorTip.showiCloudTip.toggle()
                            } label: {
                                Image(systemName: syncMonitor.syncStateSummary.symbolName)
                                    .foregroundColor(syncMonitor.syncStateSummary.symbolColor)
                            }
                            .popoverTip(iCloudTip)
                        }
                    }
                    
                }
                
                
                
                if !snippets.isEmpty {
                    if !files.isEmpty {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button{
                                showTipDev = true
                            } label:{
                                Image(systemName: "gift.circle.fill")
                            }
                            
                        }
                        
                        ToolbarItem(placement: .topBarTrailing) {
                            Button(action: toggleSnippetFiles) {
                                Image(systemName: "rectangle.grid.3x2.fill")
                            }.sheet(isPresented: $isPresentingSnippetFiles){
                                SnippetFilesView()
                            }
                            
                        }
                    }
                    
                    
                    if !tags.isEmpty {
                        ToolbarItem(placement: .topBarTrailing) {
                            Menu(
                                content: {
                                    Picker(selection: $selectedFilter, label: Image(systemName: "tag.fill")) {
                                        ForEach(tags, id: \.id) { tag in
                                            HStack {
                                                Text(tag.name!)
                                                Spacer()
                                                Image(systemName: tag.imageTag!)
                                            }
                                            .tag(Optional(tag))
                                        }
                                    }
                                },
                                label: {
                                    Image(
                                        systemName: selectedFilter != nil
                                        ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle"
                                    )
                                    .tint(Color.label)
                                })
                        }
                    }
                    
                }
            }
            
            
        } detail: {
            Group{
                HStack{
                    Image("snipkey-icon-new")
                        .resizable()
                        .frame(width: 65, height: 68)
                        .clipShape(RoundedRectangle( cornerRadius: 6))
                    
                    Text("SnipKey")
                        .font(.custom("IBMPlexMono-Medium", size: 28))
                        .fontWeight(.bold)
                        .multilineTextAlignment(.leading)
                    
                }
                .padding()
                Text("Create Once, Paste Anywhere \(selectedSnippet?.title ?? "")")
                    .font(.custom("IBMPlexMono-Medium", size: 21))
                    .fontWeight(.bold)
                    .multilineTextAlignment(.leading)
                    .padding(.bottom)
                
                Text("(Open the left menu to create a new snippet)")
                    .font(.custom("IBMPlexMono-Medium", size: 16))
                    .fontWeight(.bold)
                    .multilineTextAlignment(.leading)
            }
            
        }
        .tint(Color.label.gradient)
        .onAppear() {
            viewModel.modelContext = modelContext
            if !snippets.isEmpty {
                CreateSnippetTip.alreadyDiscovered = true
            }
        }
        .onChange(of: snippets) { oldPhase, newPhase in
            if newPhase.count % 2 == 0 && !isRequestedRating {
                print("ASK RATING")
                requestReview()
                isRequestedRating = true
            }
            
            if newPhase.count % 10 == 0 && isRequestedRating {
                print("RESET RATING")
                isRequestedRating = false
            }
            
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            if newPhase == .active {
                isKeyboardActive = isKeyboardExtensionEnabled()
            } else if newPhase == .inactive {
                print("Inactive")
            } else if newPhase == .background {
                print("Background")
            }
        }
        .toast(isPresenting: $showToast) {
            AlertToast(
                displayMode: .banner(.pop), type: .systemImage("doc.on.clipboard", .label),
                title: "Copied!",
                style: .style(
                    backgroundColor: Color.tertiarySystemBackground,
                    titleFont: .custom("IBMPlexMono-Medium", size: 14)))
        }
        
        
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
    
    func handleOnKeyboardStatusPress() {
        isPresentedGuide = true
    }
    func handleDeleteSnippet(offsets: IndexSet) {
        viewModel.deleteItems(offsets: offsets, snippets: getSnippetItems())
    }
    func toggleSnippetFiles() {
        self.isPresentingSnippetFiles.toggle()
    }
    
    init() {
        UINavigationBar.appearance().largeTitleTextAttributes = [
            .font: UIFont(name: "IBMPlexMono-Bold", size: 34)!
        ]
        UINavigationBar.appearance().titleTextAttributes = [
            .font: UIFont(name: "IBMPlexMono-Bold", size: 20)!
        ]
        
        _isKeyboardActive = State(initialValue: isKeyboardExtensionEnabled())
        
    }
    
    let gradient2 = LinearGradient(
        gradient: Gradient(stops: [
            .init(color: .systemBackground, location: 0),
            .init(color: .clear, location: 0.4),
            .init(color: .clear, location: 0.2)
        ]),
        startPoint: .bottom,
        endPoint: .top
    )
}

func isKeyboardExtensionEnabled() -> Bool {
    guard let appBundleIdentifier = Bundle.main.bundleIdentifier else {
        fatalError("isKeyboardExtensionEnabled(): Cannot retrieve bundle identifier.")
    }
    
    UserDefaults.standard.dictionaryRepresentation()
    
    guard
        let keyboards = UserDefaults.standard.dictionaryRepresentation()["AppleKeyboards"] as? [String]
    else {
        // There is no key `AppleKeyboards` in NSUserDefaults. That happens sometimes.
        return false
    }
    
    print("KEYBOARDS: \(keyboards)")
    let keyboardExtensionBundleIdentifierPrefix = appBundleIdentifier + ".SnipKeyboard"
    
    for keyboard in keyboards {
        if keyboard.hasPrefix(keyboardExtensionBundleIdentifierPrefix) {
            return true
        }
    }
    
    return false
}

#Preview {
    let container = SnipKeyDataManager().makeSharedContainer()
    
    return HomeView()
        .modelContainer(container)
}
