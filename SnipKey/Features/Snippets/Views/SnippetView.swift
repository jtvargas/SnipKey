//
//  ContentView.swift
//  SnipKey
//
//  Created by Jonathan Taveras Vargas on 3/25/24.
//

import SwiftData
import SwiftUI
import StoreKit

//func isKeyboardExtensionEnabled() -> Bool {
//    guard let appBundleIdentifier = Bundle.main.bundleIdentifier else {
//        fatalError("isKeyboardExtensionEnabled(): Cannot retrieve bundle identifier.")
//    }
//    
//    UserDefaults.standard.dictionaryRepresentation()
//    
//    guard
//        let keyboards = UserDefaults.standard.dictionaryRepresentation()["AppleKeyboards"] as? [String]
//    else {
//        // There is no key `AppleKeyboards` in NSUserDefaults. That happens sometimes.
//        return false
//    }
//    
//    let keyboardExtensionBundleIdentifierPrefix = appBundleIdentifier + ".SnipKeyboard"
//    
//    for keyboard in keyboards {
//        if keyboard.hasPrefix(keyboardExtensionBundleIdentifierPrefix) {
//            return true
//        }
//    }
//    
//    return false
//}

struct SnippetView: View {
    @AppStorage("isRequestedRating") var isRequestedRating: Bool = false
    
    @Environment(\.requestReview) var requestReview
    @Environment(\.modelContext) var modelContext
    @Environment(\.scenePhase) var scenePhase
    
    @State var viewModel = SnippetViewModel()
    @State private var selectedFilter: SnipTag? = nil
    @State var showSnippedDetailSheet = false
    
    
    @Query(sort: \SnippetItem.creationDate, order: .reverse, animation: .bouncy) private var snippets:
    [SnippetItem]
    @Query(sort: \SnipTag.creationDate) private var tags: [SnipTag]
    @Query(sort: \SnippetFile.id, order: .reverse, animation: .bouncy) private var files:
    [SnippetFile]
    
    //    For some reasons this filter predicate not work, wait until new swiftData version improves this
    //    @Query(filter: #Predicate<SnippetItem>{
    //        $0.tag == .personal
    //    }, sort: \SnippetItem.timestamp, order: .reverse, animation: .bouncy) private var snippetsPersonal: [SnippetItem]
    //
    //    @Query(filter: #Predicate<SnippetItem>{
    //        $0.tag == .work
    //    }, sort: \SnippetItem.timestamp, order: .reverse, animation: .bouncy) private var snippetsWork: [SnippetItem]
    
    //    @Query(filter: #Predicate<SnippetItem> {$0.tag == selectedFilter}) private var snippetsFiltered: [SnippetItem]
    
    //    @Query() private var snipKeyboardSetting: [SnipKeyboardSettings]
    //
    @State private var showModal = false
    @State var isPresentingSettings: Bool = false
    @State var isPresentedFormModal: Bool = false
    @State var isPresentedGuide: Bool = false
    @State var isPresentedWelcomeInfo: Bool = false
    @State var isKeyboardActive: Bool = false
    @State var isPresentingSnippetFiles: Bool = false
    
    var body: some View {
        NavigationStack {
            VStack {
                if !snippets.isEmpty {
                    KeyboardStatusView(
                        isActive: isKeyboardActive,
                        onKeyboardStatusPress: handleOnKeyboardStatusPress
                    )
                    .sheet(
                        isPresented: $isPresentedGuide,
                        content: {
                            KeyboardHelpGuideView(isPresented: $isPresentedGuide)
                        })
                    Form {
                        
                        Section(
                            header: HStack {
                                Text("Snippets")
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
                                ForEach(getSnippetItems(), id: \.self.id) { snippetItem in
                                    NavigationLink(destination: SnippetViewDetail(item: snippetItem)) {
                                        SnippetListItem(item: snippetItem)
                                    }
                                }
                                .onDelete(perform: { indexSet in
                                    self.handleDeleteSnippet(offsets: indexSet)
                                })
                            }
                        }
                    }
                }
                
            }
            .navigationTitle(snippets.isEmpty ? "" : "SnipKey")
            .font(.custom("IBMPlexMono-Medium", size: 16))
            .tint(Color.label)
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                if snippets.isEmpty {
                    SnippetListEmpty()
                }
            }
            .toolbar {
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
                
                if !snippets.isEmpty {
                    if !files.isEmpty {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button(action: toggleSnippetFiles) {
                                Image(systemName: "rectangle.grid.3x2.fill")
                            }.sheet(isPresented: $isPresentingSnippetFiles){
                                SnippetFilesView()
                            }
                           
                        }
                    }
                   
                    
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu(
                            content: {
                                Picker(selection: $selectedFilter, label: Image(systemName: "tag.fill")) {
                                    ForEach(tags, id: \.id) { tag in
                                        HStack {
                                            Text(tag.name)
                                            Spacer()
                                            Image(systemName: tag.imageTag)
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
                
                ToolbarItem(placement: .bottomBar) {
                    HStack(alignment: .center) {
                        Button(action: toggleWelcomeInfo) {
                            Image(systemName: "info.circle.fill")
                                .tint(Color.label.gradient)
                                .font(.system(size: 24))
                        }.sheet(isPresented: $isPresentedWelcomeInfo) {
                            OnboardingView(appName: "SnipKey",showOnboarding: $isPresentedWelcomeInfo, features: [
                                Feature(title: "Create Snippets/Shortcuts", description: "Craft and instantly use snippets across any apps.", icon: "doc.on.doc.fill"),
                                Feature(title: "Tag & Organize", description: "Sort snippets swiftly with tags.", icon: "tag.fill"),
                                Feature(title: "Keyboard Quick-Use", description: "Access all snippets directly through the keyboard extension..", icon: "keyboard.fill"),
                                Feature(title: "Lock Snippets", description: "Secure sensitive data with encryption and biometrics.", icon: "lock.fill"),
                            ], color: Color.label)
                        }
                        Spacer()
                        Button(action: toggleFormModal) {
                            Image(systemName: "plus.app.fill")
                                .tint(Color.label.gradient)
                                .font(.system(size: 28))
                            
                        }
                        .sheet(isPresented: $isPresentedFormModal) {
                            NavigationStack {
                                SnippetForm(snippet: nil, isFormVisible: $isPresentedFormModal)
                            }
                            .presentationBackground(Color.clear)
                        }
                        
                        Spacer()
                        Button(action: toggleSettingsModal) {
                            Image(systemName: "gearshape.circle.fill")
                                .tint(Color.label.gradient)
                                .font(.system(size: 24))
                        }.sheet(isPresented: $isPresentingSettings) {
                            SettingsView(isPresentingSettings: $isPresentingSettings)
                                
                        }
                        
                    }
                    .padding(.bottom, 10)
                    
                }
            }
        }
        .tint(Color.label.gradient)
        .onAppear {
            viewModel.modelContext = modelContext
//            isKeyboardActive = isKeyboardExtensionEnabled()
//            isKeyboardActive = checkFullAccess()
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
    
    func toggleFormModal() {
        self.isPresentedFormModal.toggle()
    }
    
    func toggleSnippetFiles() {
        self.isPresentingSnippetFiles.toggle()
    }
    
    func toggleWelcomeInfo() {
        self.isPresentedWelcomeInfo.toggle()
    }
    func toggleSettingsModal() {
        self.isPresentingSettings.toggle()
        print("toggleSettingsModal")
    }
    
    func handleOnKeyboardStatusPress() {
        isPresentedGuide = true
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
    
    func handleDeleteSnippet(offsets: IndexSet) {
        viewModel.deleteItems(offsets: offsets, snippets: snippets)
    }
}

#Preview {
    let container = SnipKeyDataManager().makeSharedContainer()
    
    return SnippetView()
        .modelContainer(container)
    
}
