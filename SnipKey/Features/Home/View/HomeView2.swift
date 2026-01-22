//
//  HomeView2.swift
//  SnipKey
//
//  Created by Jonathan Taveras Vargas on 11/7/25.
//

import SwiftUI
import SwiftData
import CloudKitSyncMonitor
import AlertToast
import UniformTypeIdentifiers
import TipKit



struct HomeView2: View {
    
    @AppStorage("showTipDev") var isPresentingTipsView: Bool = false
    @AppStorage("isRequestedRating") var isRequestedRating: Bool = false
    @AppStorage("isKeyboardShortcutEnabled") var isKeyboardShortcutEnabled: Bool = false
    @Environment(\.requestReview) var requestReview
    @Environment(\.modelContext) var modelContex
    
    @State var viewModel = SnippetViewModel()
    
    
    @Query(sort: \SnippetItem.creationDate, order: .reverse, animation: .bouncy) private var snippets:
    [SnippetItem]
    @Query(sort: \SnipTag.creationDate) private var tags: [SnipTag]
    
    @State var navigationPath = NavigationPath()
    
    var isNavigating: Bool {
        !navigationPath.isEmpty
    }
    
    @State var editMode: EditMode = .inactive
    @State  var snippetsSelection = Set<SnippetItem>()
    @State var text: String = ""
    @State var isPresentingSettings: Bool = false
    @State var isPresentedMoveOrCreateTags: Bool = false
    @State var isPresentedFormModal: Bool = false
    @State var isPresentedKeyboardGuide: Bool = false
    @State var isPresentedWelcomeInfo: Bool = false
    @State private var showToast = false
    @State  var selectedFilter: SnipTag? = nil
    @State private var showDeleteConfirmation = false
    @State private var isNavigatingSnippet = false // to track if navigates to a snippet detail
    
    @available(iOS 14.0, *)
    @ObservedObject var syncMonitor = SyncMonitor.shared
    
    // Tips
    private let createSnippetTip = CreateSnippetTip()
    private let iCloudTip = CloudIndicatorTip()
    private var considerTipDev = ConsiderTipDev()
    
    
    
    var body: some View {
        TabView {
            Tab {
 
                NavigationStack(path: $navigationPath) {
                    ListItemsView()
                        .sheet(isPresented: $isPresentedMoveOrCreateTags) {
                            MoveOrCreateTagSheet(
                                snippetsSelection: $snippetsSelection,
                                onSave: {
                                    snippetsSelection.removeAll()
                                }
                            )
                            .presentationDetents([.height(425)])
                        }
                        .toolbar {
                            ToolbarItem(placement: .topBarLeading){
                                HStack{
                                    InfoButtonView()
                                    IcloudSaveIndocatorView()
                                    TipsDevButtonView()
                                }
                                
                            }
                            ToolbarItem(placement: .primaryAction){
                                if snippetsSelection.isEmpty && !editMode.isEditing  {
                                    FilterListButtonView()
                                } else {
                                    EditListButtonView()
                                }
                                
                                
                            }
                            ToolbarItem(placement: .primaryAction){
                                
                                EditButton()
                            }
                        }
                        .environment(\.editMode, $editMode)
                    
                }
                
                .safeAreaInset(edge: .bottom, alignment: .center) {
                    AddSnippetButtonView()
                }
                .animation(.spring(response: 0.4, dampingFraction: 0.6), value: isNavigating)
                
                TipView(considerTipDev) { action in
                    if action.id == "support" {
                        isPresentingTipsView = true
                    }

                }
                .padding(20)
            } label: {
                Label("Snippets", systemImage: "list.dash.header.rectangle.fill")
            }
            
            
            Tab {
                //                Color.pink.ignoresSafeArea()
                SettingsView(isPresentingSettings: $isPresentingSettings)
            } label: {
                Label("Settings", systemImage: "gearshape.circle.fill")
            }
            
            
            Tab(role: .search) {
                SearchView()
            }
            
            
        }
        .onAppear() {
            viewModel.modelContext = modelContex
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
            
            if newPhase.count % 40 == 0 && isRequestedRating {
                print("RESET RATING")
                isRequestedRating = false
            }
            
        }
        .tint(.yellow)
        .toast(isPresenting: $showToast) {
            AlertToast(
                displayMode: .banner(.pop), type: .systemImage("doc.on.clipboard", .label),
                title: "Copied!",
                style: .style(
                    backgroundColor: Color.tertiarySystemBackground,
                    titleFont: .custom("IBMPlexMono-Medium", size: 14)))
        }
    }
    
    var currentSnippets: [SnippetItem]  {
        return getSnippetItems()
    }
    
    private var navigationSubtitleText: String {
        var subtitle = ""
        
        // Add filter info
        if let filter = selectedFilter {
            subtitle = "Filtered by \"\(filter.name ?? "")\""
        }
        
        // Add selection count
        if snippetsSelection.count > 0 {
            let selectionText = "Selected: \(snippetsSelection.count)"
            if subtitle.isEmpty {
                subtitle = selectionText
            } else {
                subtitle += " • \(selectionText)"
            }
        }
        
        return subtitle
    }

    
    
    @ViewBuilder
    func ListItemsView() -> some View {
        
        
        if currentSnippets.isEmpty {
            
            if selectedFilter != nil {
                ContentUnavailableView(
                    "No Snippets in \"\(selectedFilter?.name ?? "")\"",
                    systemImage: selectedFilter?.imageTag ?? "tag.slash.fill",
                    description: Text("No snippets found with this tag.\nPress the **+** button to create a new snippet.")
                )            } else {
                    ContentUnavailableView(
                        "No Snippets Yet",
                        systemImage: "checklist.unchecked",
                        description: Text("Press the **+** button to create your first snippet")
                    )
                }
            
        } else {
            //            TODO: review design UI for this appear more in the list
   
            List(currentSnippets, id: \.self, selection: editMode.isEditing == true ? $snippetsSelection : nil) { snippetItem in
                NavigationLink(value: snippetItem) {
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
            .onChange(of: editMode.isEditing) { old, isEditing in
                if isEditing == false {
                    snippetsSelection.removeAll()
                }
            }
            .safeAreaPadding(EdgeInsets(top: 0, leading: 0, bottom: 60, trailing: 0)) // Pushes content upwards, creating space at the bottom
            .navigationDestination(for: SnippetItem.self) { item in
                SnippetViewDetail(item: item)
            }
            .navigationTitle("Snippets")
            .navigationSubtitle(navigationSubtitleText)
            // also support subtitle if filter is selected show the name of the filter as well, like filtered by "..."
//            .navigationSubtitle("\(snippetsSelection.count > 1 ? "Selected: \(snippetsSelection.count)") : """)
        }
        

        
    }
    
    func deleteItemsSelected() {
        guard !snippetsSelection.isEmpty else { return }
        
        viewModel.deleteSelectedItems(snippets: Array(snippetsSelection))
        snippetsSelection.removeAll()
    }
    
    @ViewBuilder
    func DeleteButtonView() -> some View {
        Button {
            if snippetsSelection.count > 1 {
                showDeleteConfirmation = true
            } else {
                deleteItemsSelected()
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "trash.fill")
                    .font(.system(size: 16))
            }
            .foregroundStyle(Color.red)
        }
        .padding(4)
        .disabled(snippetsSelection.isEmpty)
        .opacity(snippetsSelection.isEmpty ? 0.5 : 1)
        .alert(
            "Delete Selected Items?",
            isPresented: $showDeleteConfirmation
        ) {
            Button("Cancel", role: .cancel) {}
            Button("Delete \(snippetsSelection.count) Snippet\(snippetsSelection.count == 1 ? "" : "s")", role: .destructive) {
                deleteItemsSelected()
                editMode = .inactive
            }
        } message: {
            Text("This will permanently remove the selected snippet\(snippetsSelection.count == 1 ? "" : "s") from your collection.")
        }
    }
    
    @ViewBuilder
    func EditListButtonView() -> some View {
        GlassEffectContainer() {
            HStack() {
                DeleteButtonView()
                
                Button {
                    // be able to have a sheet to select the tag we want to move or create tag for items selected
                    isPresentedMoveOrCreateTags = true
                } label: {
                    Image(systemName: "tag.square.fill")
                        .font(Font.system(size: 16))
                        .foregroundStyle(Color.yellow)
                }
                .padding(4)
                .disabled(snippetsSelection.isEmpty)
                .opacity(snippetsSelection.isEmpty ? 0.5 : 1)
            }
        }
        
        
    }
    
    @ViewBuilder
    func FilterListButtonView() -> some View {
        if selectedFilter != nil {
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    selectedFilter = nil
                }
            } label: {
                Image(systemName: "xmark.circle")
                    .font(Font.system(size: 21))
                //                                .foregroundStyle(.white, Color.red)
            }
            .padding()
            ////                        .glassEffect(.regular.tint(.clear).interactive(), in: Rectangle())
            //                        .clipShape(Rectangle())
            //                        .contentShape(Rectangle())
            //                        .transition(.scale.combined(with: .opacity))
        }else {
            Menu(
                content: {
                    Picker(selection: $selectedFilter, label: Image(systemName: "tag.fill")) {
                        ForEach(tags, id: \.id) { tag in
                            Label {
                                Text(tag.name!)
                            } icon: {
                                HStack(spacing: 4) {
                                    if tag.colorHex != nil {
                                        Image(systemName: "circle.fill")
                                            .foregroundColor(Color(hex: tag.colorHex!) ?? .gray)
                                            .font(.system(size: 8))
                                    }
                                    Image(systemName: tag.imageTag!)
                                }
                            }
                            .tag(Optional(tag))
                        }
                    }
                },
                label: {
                    Image(
                        systemName: selectedFilter != nil
                        ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease"
                    )
                    //                            .font(Font.system(size: 32))
                    .tint(Color.label)
                    
                    //
                })
            .padding()
            .buttonStyle(.glass)
        }
        
        
    }
    
    
    
    @ViewBuilder
    func IcloudSaveIndocatorView() -> some View {
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
    
    @ViewBuilder
    func TipsDevButtonView() -> some View {
        Button {
            isPresentingTipsView = true
        } label : {
            Image(systemName: "gift.fill")
                .foregroundStyle(Color.yellow)
        }
    }
    
    @ViewBuilder
    func InfoButtonView() -> some View {
        Button {
            self.isPresentedWelcomeInfo.toggle()
        } label : {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(Color.label.gradient)
        }
        .sheet(isPresented: $isPresentedWelcomeInfo) {
            OnboardingView(appName: "SnipKey", showOnboarding: $isPresentedWelcomeInfo, features: [
                Feature(title: "Create & Use Snippets", description: "Craft snippets, use them anywhere.", icon: "doc.on.doc.fill"),
                Feature(title: "Keyboard Extension", description: "Access snippets directly from keyboard.", icon: "keyboard.fill"),
                Feature(title: "Organize with Tags", description: "Sort snippets using quick tags.", icon: "tag.fill"),
                Feature(title: "Secure Data", description: "Encrypt sensitive snippets.", icon: "lock.fill"),
                Feature(title: "iCloud Sync", description: "Access across all your devices.", icon: "cloud.fill"),
            ], color: Color.label)
        }
    }
    
    @ViewBuilder
    func AddSnippetButtonView() -> some View {
        if !isNavigating {
            ZStack(alignment: .bottomTrailing) {
                Color.clear.ignoresSafeArea()
                
                VStack(alignment: .leading) {
                    HStack(spacing: 8) {
                        // Support/Tip Button (far left)
                        SupportTipButton(action: {
                            isPresentingTipsView = true
                        })
                        .padding(12)
                        .buttonStyle(.glass)
                        .clipShape(Circle())
                        .contentShape(Circle())
                        
                        KeyboardStatusView(
                            isShortcutsActive: isKeyboardShortcutEnabled,
                            onKeyboardStatusPress: {
                                isPresentedKeyboardGuide = true
                            }
                        )
                        .padding()
                        .buttonStyle(.glass)
                        .clipShape(Circle())
                        .contentShape(Circle())
                        .sheet(
                            isPresented: $isPresentedKeyboardGuide,
                            content: {
                                KeyboardHelpGuideView(isPresented: $isPresentedKeyboardGuide)
                            })
                        Spacer()
                        
                        
                        
                        
                        Button {
                            Task { await ConsiderTipDev.didCreateSnippetTrigger.donate() }
                            self.isPresentedFormModal.toggle()
                            selectedFilter = nil
                        } label: {
                            
                            Image(systemName: "plus")
                                .foregroundStyle(.white)
                                .font(Font.system(size: 32))
                            
                        }
                        .padding()
                        .glassEffect(.regular.tint(.accentColor).interactive(), in: Circle())
                        .clipShape(Circle())
                        .contentShape(Rectangle())
                        .padding(.bottom, 12)
                        .popoverTip(createSnippetTip)
                    }
                    
                    
                }
                .padding(.horizontal)
                
                .sheet(isPresented: $isPresentedFormModal) {
                    NavigationStack {
                        SnippetForm(snippet: nil, isFormVisible: $isPresentedFormModal)
                    }
                    .presentationBackground(Color.clear)
                }
            }
            .transition(.opacity.combined(with: .offset(x: 10, y: 20)))
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
    
    func handleDeleteSnippet(offsets: IndexSet, items: [SnippetItem]) {
        viewModel.deleteItems(offsets: offsets, snippets: items)
    }
}

// MARK: - Support Tip Button Component
struct SupportTipButton: View {
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Image(systemName: "gift.fill")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Color.yellow)
        }
    }
}

#Preview {
    let container = SnipKeyDataManager().makeSharedContainer()
    let settingsViewModel = SettingsViewModel(modelContext: container.mainContext)
    
    HomeView2()
        .onAppear {
            settingsViewModel.modelContext = container.mainContext
            settingsViewModel.setupKeyboardSettings()
        }
        .environment(settingsViewModel)
        .modelContainer(container)
}
