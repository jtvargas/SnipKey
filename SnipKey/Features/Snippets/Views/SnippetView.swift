//
//  ContentView.swift
//  SnipKey
//
//  Created by Jonathan Taveras Vargas on 3/25/24.
//

import SwiftData
import SwiftUI

func isKeyboardExtensionEnabled() -> Bool {
    guard let appBundleIdentifier = Bundle.main.bundleIdentifier else {
        fatalError("isKeyboardExtensionEnabled(): Cannot retrieve bundle identifier.")
    }
    
    guard let keyboards = UserDefaults.standard.dictionaryRepresentation()["AppleKeyboards"] as? [String] else {
        // There is no key `AppleKeyboards` in NSUserDefaults. That happens sometimes.
        return false
    }
    
    let keyboardExtensionBundleIdentifierPrefix = appBundleIdentifier + ".SnipKeyboard"
    
    for keyboard in keyboards {
        if keyboard.hasPrefix(keyboardExtensionBundleIdentifierPrefix) {
            return true
        }
    }
    
    return false
}

struct SnippetView: View {
    @State var showSnippedDetailSheet = false
    @Environment(\.modelContext) var modelContext
    @Environment(\.scenePhase) var scenePhase
    @State var viewModel = SnippetViewModel()
    @State private var selectedFilter: SnipTag? = nil
    @Query(sort: \SnippetItem.creationDate, order: .reverse, animation: .bouncy) private var snippets: [SnippetItem]
    @Query(sort: \SnipTag.name) private var tags: [SnipTag]
    
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

    func toggleFormModal() {
        self.isPresentedFormModal.toggle()
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
    
    
    var body: some View {
        NavigationStack {
            VStack {
                if !snippets.isEmpty {
                    KeyboardStatusView(isActive: isKeyboardActive, onKeyboardStatusPress: handleOnKeyboardStatusPress)
                        .sheet(isPresented: $isPresentedGuide, content: {
                            KeyboardHelpGuideView(isPresented: $isPresentedGuide)
                        })
                    Form {
                       
                        Section(header:  HStack{
                            Text("Snippets")
                            Spacer()
                            
                            if selectedFilter != nil {
                                Button{
                                    selectedFilter = nil
                                }label:{
                                    HStack{
                                        Image(systemName: "minus.circle.fill")
                                        Text("Remove Filter")
                                            .font(.custom("IBMPlexMono-Medium", size: 14))
                                    }
                                    
                                }
                            }
                           
                        }) {
                            List {
                                ForEach(getSnippetItems(), id: \.self.id) { snippetItem in
                                    NavigationLink(destination: SnippetViewDetail(item: snippetItem)) {
                                        SnippetListItem(item: snippetItem)
                                    }
                                    .listRowBackground(Color.tertiarySystemBackground)
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
            .navigationBarTitleDisplayMode(.large)
            .safeAreaInset(edge: .bottom) {
                if snippets.isEmpty {
                    SnippetListEmpty()
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
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
                                .tint(Color.label)
                                .font(.system(size: 24))
                        }.sheet(isPresented: $isPresentedWelcomeInfo) {
                            WelcomeView(skipCallback: toggleWelcomeInfo)
                        }
                        Spacer()
                        Button(action: toggleFormModal) {
                            Image(systemName: "plus.app.fill")
                                .tint(Color.label)
                                .font(.system(size: 28))
                            
                        }
                        .sheet(isPresented: $isPresentedFormModal) {
                            NavigationStack {
                                SnippetForm(snippet: nil, isFormVisible: $isPresentedFormModal)
                            }
                        }
                        
                        Spacer()
                        Button(action: toggleSettingsModal) {
                            Image(systemName: "gearshape.circle.fill")
                                .tint(Color.label)
                                .font(.system(size: 24))
                        }.sheet(isPresented: $isPresentingSettings) {
                            SettingsView( isPresentingSettings: $isPresentingSettings)
                        }
                        
                    }
                    .padding(.bottom, 10)
                    
                }
            }
        }
        .tint(Color.label)
        .onAppear {
            viewModel.modelContext = modelContext
            isKeyboardActive = isKeyboardExtensionEnabled()
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
        
    }
}

#Preview {
    let container = SnipKeyDataManager().makeSharedContainer()
    
    return SnippetView()
        .modelContainer(container)
    
}
