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
import UserNotifications
import Pow
import UIKit



struct HomeView2: View {
    
    @AppStorage("showTipDev") var isPresentingTipsView: Bool = false
    @AppStorage("isRequestedRating") var isRequestedRating: Bool = false
    @AppStorage("isKeyboardShortcutEnabled") var isKeyboardShortcutEnabled: Bool = false
    @Environment(\.requestReview) var requestReview
    @Environment(\.modelContext) var modelContex
    @Environment(\.scenePhase) private var scenePhase
    
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
    @State var isPresentedReminders: Bool = false
    @State private var pendingReminderCount: Int = 0
    @State var isPresentedMoveOrCreateTags: Bool = false
    @State var isPresentedFormModal: Bool = false
    @State var isPresentedKeyboardGuide: Bool = false
    @State var isPresentedWelcomeInfo: Bool = false
    @State private var clipboardSuggestion: ClipboardSnippetSuggestion?
    @State private var snippetFormDraft: SnippetFormDraft?
    @State private var dismissedClipboardSnippetChangeCount: Int?
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
                SnippetsTabView()
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
            refreshReminderCount()
            recheckClipboardSuggestion()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                refreshReminderCount()
                recheckClipboardSuggestion()
            }
        }
        .onChange(of: isPresentedReminders) { _, isPresented in
            // Returning from the Reminders sheet (after delete/clear) → re-read the count.
            if !isPresented { refreshReminderCount() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NotificationPresenter.remindersDidChange)) { _ in
            refreshReminderCount()
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

    @ViewBuilder
    private func SnippetsTabView() -> some View {
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
                .sheet(isPresented: $isPresentedReminders) {
                    RemindersView()
                }
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        HStack {
                            InfoButtonView()
                            IcloudSaveIndocatorView()
//                                    TipsDevButtonView()
                            RemindersButtonView()
                        }
                    }

                    ToolbarItem(placement: .primaryAction) {
                        if snippetsSelection.isEmpty && !editMode.isEditing  {
                            FilterListButtonView()
                        } else {
                            EditListButtonView()
                        }
                    }

                    ToolbarItem(placement: .primaryAction) {
                        EditButton()
                    }
                }
                .environment(\.editMode, $editMode)
        }
        .sheet(isPresented: $isPresentedFormModal, onDismiss: {
            snippetFormDraft = nil
        }) {
            NavigationStack {
                SnippetForm(
                    snippet: nil,
                    initialDraft: snippetFormDraft,
                    isFormVisible: $isPresentedFormModal
                )
            }
            .presentationBackground(Color.clear)
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
            VStack(spacing: 16) {
                ClipboardSuggestionBannerView()

                if selectedFilter != nil {
                    ContentUnavailableView(
                        "No Snippets in \"\(selectedFilter?.name ?? "")\"",
                        systemImage: selectedFilter?.imageTag ?? "tag.slash.fill",
                        description: Text("No snippets found with this tag.\nPress the **+** button to create a new snippet.")
                    )
                } else {
                        ContentUnavailableView(
                            "No Snippets Yet",
                            systemImage: "checklist.unchecked",
                            description: Text("Press the **+** button to create your first snippet")
                        )
                }
            }
            .navigationTitle("Snippets")
            .navigationSubtitle(navigationSubtitleText)
            
        } else {
            //            TODO: review design UI for this appear more in the list

            List(selection: editMode.isEditing == true ? $snippetsSelection : nil) {
                ClipboardSuggestionBannerView()

                ForEach(currentSnippets, id: \.self) { snippetItem in
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

                Text("Thanks For Using the App.")
                    .font(.custom("IBMPlexMono-Regular", size: 12))
                    .foregroundStyle(Color.tertiaryLabel)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .multilineTextAlignment(.center)
                    .padding(.vertical, 18)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
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
    func RemindersButtonView() -> some View {
        Button {
            isPresentedReminders = true
        } label: {
            Image(systemName: "bell")
                .foregroundStyle(Color.label.gradient)
                .overlay(alignment: .topLeading) {
                    if pendingReminderCount > 0 {
                        Text("\(pendingReminderCount)")
                            .font(.custom("IBMPlexMono-Medium", size: 9))
                            .foregroundStyle(.white)
                            .padding(2)
                            .frame(minWidth: 15, minHeight: 15)
                            .background(Circle().fill(Color.customError))
                            .offset(x: -7, y: -2)
                    }
                }
        }
    }

    /// Reads the number of upcoming (pending) reminders so the bell can badge it.
    private func refreshReminderCount() {
        UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
            let count = requests.filter {
                $0.identifier.hasPrefix(LocalNotificationScheduler.identifierPrefix)
            }.count
            DispatchQueue.main.async { pendingReminderCount = count }
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
                Feature(title: "Snippets", description: "Save text, URLs, images and PDFs.", icon: "doc.on.doc.fill"),
                Feature(title: "Keyboard", description: "Access snippets from any app.", icon: "keyboard.fill"),
                Feature(title: "Slash Commands", description: "Type / to find and paste snippets.", icon: "chevron.left.forwardslash.chevron.right"),
                Feature(title: "Tags", description: "Organize with custom tags.", icon: "tag.fill"),
                Feature(title: "Biometric Lock", description: "Secure snippets with FaceID.", icon: "lock.fill"),
                Feature(title: "iCloud Sync", description: "Syncs across all your devices.", icon: "cloud.fill"),
                Feature(title: "Open Source", description: "View code on GitHub.", icon: "curlybraces"),
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
                            snippetFormDraft = nil
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

    @ViewBuilder
    private func ClipboardSuggestionBannerView() -> some View {
        if let clipboardSuggestion, !editMode.isEditing {
            ClipboardSnippetBanner(
                suggestion: clipboardSuggestion,
                onPaste: presentClipboardDraft,
                onDismiss: dismissClipboardSuggestion
            )
            .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    private func refreshClipboardSuggestion() {
        let pasteboard = UIPasteboard.general
        let changeCount = pasteboard.changeCount

        guard dismissedClipboardSnippetChangeCount != changeCount else {
            clipboardSuggestion = nil
            return
        }

        if pasteboard.hasImages {
            setClipboardSuggestion(kind: .image, changeCount: changeCount)
            return
        }

        if pasteboard.hasURLs {
            setClipboardSuggestion(kind: .url, changeCount: changeCount)
            return
        }

        guard pasteboard.hasStrings else {
            clipboardSuggestion = nil
            return
        }

        Task {
            let patterns = try? await pasteboard.detectedPatterns(
                for: [\UIPasteboard.DetectedValues.probableWebURL]
            )

            await MainActor.run {
                guard UIPasteboard.general.changeCount == changeCount,
                      dismissedClipboardSnippetChangeCount != changeCount else { return }

                if patterns?.contains(\UIPasteboard.DetectedValues.probableWebURL) == true {
                    setClipboardSuggestion(kind: .url, changeCount: changeCount)
                } else {
                    setClipboardSuggestion(kind: .text, changeCount: changeCount)
                }
            }
        }
    }

    private func recheckClipboardSuggestion() {
        dismissedClipboardSnippetChangeCount = nil
        refreshClipboardSuggestion()
    }

    private func setClipboardSuggestion(kind: ClipboardSnippetKind, changeCount: Int) {
        let nextSuggestion = ClipboardSnippetSuggestion(kind: kind, changeCount: changeCount)
        if clipboardSuggestion != nextSuggestion {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                clipboardSuggestion = nextSuggestion
            }
        }
    }

    private func dismissClipboardSuggestion() {
        guard let clipboardSuggestion else { return }
        dismissedClipboardSnippetChangeCount = clipboardSuggestion.changeCount
        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
            self.clipboardSuggestion = nil
        }
    }

    private func presentClipboardDraft(_ draft: SnippetFormDraft) {
        snippetFormDraft = draft
        if let clipboardSuggestion {
            dismissedClipboardSnippetChangeCount = clipboardSuggestion.changeCount
            self.clipboardSuggestion = nil
        }
        isPresentedFormModal = true
        selectedFilter = nil
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
                .conditionalEffect(
                    .repeat(
                      .glow(color: .yellow, radius: 50),
                      every: 1.5
                    ),
                    condition: true
                )
                .conditionalEffect(.repeat(.wiggle(rate: .fast), every: .seconds(1)), condition: true)
        }
    }
}

private enum ClipboardSnippetKind: Equatable {
    case text
    case url
    case image

    var title: String {
        switch self {
        case .text:
            return "Text is in your clipboard"
        case .url:
            return "A URL is in your clipboard"
        case .image:
            return "An image is in your clipboard"
        }
    }

    var subtitle: String {
        "Create a snippet from your clipboard."
    }

    var iconName: String {
        switch self {
        case .text:
            return "character.cursor.ibeam"
        case .url:
            return "link"
        case .image:
            return "photo"
        }
    }

    var snipType: SnipType {
        switch self {
        case .text:
            return .txt
        case .url:
            return .url
        case .image:
            return .image
        }
    }
}

private struct ClipboardSnippetSuggestion: Equatable {
    let kind: ClipboardSnippetKind
    let changeCount: Int
}

private struct ClipboardSnippetBanner: View {
    let suggestion: ClipboardSnippetSuggestion
    let onPaste: (SnippetFormDraft) -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Button {
                onPaste(SnippetFormDraft(type: suggestion.kind.snipType, pasteClipboardOnAppear: true))
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: suggestion.kind.iconName)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Color.secondaryLabel)
                        .frame(width: 28, height: 28)
                        .background(Color.secondarySystemBackground)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(suggestion.kind.title)
                            .font(.custom("IBMPlexMono-SemiBold", size: 13))
                            .foregroundStyle(Color.label)
                            .lineLimit(2)

                        Text(suggestion.kind.subtitle)
                            .font(.custom("IBMPlexMono-Regular", size: 11))
                            .foregroundStyle(Color.secondaryLabel)
                            .lineLimit(2)
                    }

                    Spacer(minLength: 8)

                    Text("Create")
                        .font(.custom("IBMPlexMono-SemiBold", size: 12))
                        .foregroundStyle(Color.label)
                }
                .frame(maxWidth: .infinity)
                .padding(.leading, 10)
                .padding(.vertical, 9)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Create snippet from clipboard")

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.secondaryLabel)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Dismiss clipboard suggestion")
        }
        .background(Color.tertiarySystemBackground)
        .accessibilityElement(children: .contain)
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
