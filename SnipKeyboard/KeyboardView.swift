//
//  KeyboardView.swift
//  SnipKeyboard
//
//  Created by Jonathan Taveras Vargas on 3/31/24.
//

import SwiftData
import SwiftUI
import AlertToast

// MARK: - Sort Option

enum SortOption: String, CaseIterable {
    case alphabetical = "Alphabetical"
    case dateCreated = "Date Created"
    case recentlyUsed = "Recently Used"

    var imageName: String {
        switch self {
        case .dateCreated:   return "calendar.circle"
        case .recentlyUsed:  return "timer.circle"
        case .alphabetical:  return "textformat.abc"
        }
    }
}

// MARK: - Keyboard Snippet View

struct KeyboardView: View {
    @Environment(\.modelContext) var modelContext
    @Environment(\.keyboardActions) private var keyboardActions
    @Environment(SettingsViewModel.self) private var settingsViewModel
    @Environment(QWERTYKeyboardState.self) private var qwertyStateFromEnvironment: QWERTYKeyboardState?

    @Query(sort: \SnippetItem.creationDate, order: .reverse) private var snippets: [SnippetItem]
    @Query(sort: \SnipTag.name) private var tags: [SnipTag]
    @Query() private var settings: [SettingsModel]

    let deviceBiometrics = DeviceBiometrics()

    // Snippet interaction state
    @State private var isUnlocked: Bool = false
    @State private var showCreateSnippetCTA = false
    @State private var showCreatedToast = false
    @State private var showToast = false
    @State private var selectedText: String = ""
    @State var snippetViewModel = SnippetViewModel()

    // Tag filter
    @State private var selectedFilter: SnipTag? = nil

    // Sort
    @State private var sortOption: SortOption = .recentlyUsed
    @State private var sortOrder: SortOrder = .forward

    // Delete long-press
    @State private var isLongPressing = false
    @State private var deleteTimer: Timer?

    // Notification observers
    @State private var notificationObservers: [Any] = []

    // MARK: - Computed Properties

    private var currentKeyboardSettings: SettingsModel {
        settings.first ?? SettingsModel(afterPasteAction: .space)
    }

    private var sortedSnippets: [SnippetItem] {
        let filtered: [SnippetItem]
        if let filter = selectedFilter {
            filtered = snippets.filter { $0.customTag == filter }
        } else {
            filtered = Array(snippets)
        }
        return filtered.sorted { first, second in
            switch sortOption {
            case .dateCreated:
                let d1 = first.creationDate ?? .distantPast
                let d2 = second.creationDate ?? .distantPast
                return sortOrder == .forward ? d1 > d2 : d1 < d2
            case .recentlyUsed:
                let d1 = first.lastTimeUsed ?? .distantPast
                let d2 = second.lastTimeUsed ?? .distantPast
                return sortOrder == .forward ? d1 > d2 : d1 < d2
            case .alphabetical:
                let t1 = first.title?.lowercased() ?? ""
                let t2 = second.title?.lowercased() ?? ""
                return sortOrder == .forward ? t1 < t2 : t1 > t2
            }
        }
    }

    // MARK: - Grid Layout

    private let gridColumns = [
        GridItem(.adaptive(minimum: 150, maximum: 200), spacing: 8)
    ]

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Top toolbar
            ToolbarView()

            // Scrollable snippet grid
            ScrollView {
                // Create snippet CTA (when text is selected)
                CreateSnippetCTA()

                LazyVGrid(columns: gridColumns, spacing: 8) {
                    ForEach(sortedSnippets, id: \.self.id) { snippet in
                        Button {
                            sentValue(snippet: snippet)
                        } label: {
                            SnippetListItemMinimal(item: snippet)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            }

            // Bottom bar: filter + actions
            BottomBar()
        }
        .frame(height: KeyboardDimensions.totalHeight(forScreenWidth: UIScreen.main.bounds.width))
        .onAppear {
            settingsViewModel.modelContext = modelContext
            snippetViewModel.modelContext = modelContext
            setupNotificationObservers()
        }
        .onDisappear {
            removeNotificationObservers()
            stopRapidDeletion()
        }
        .toast(isPresenting: $showToast) {
            AlertToast(
                displayMode: .banner(.pop),
                type: .systemImage("doc.on.clipboard", .label),
                title: !checkFullAccess()
                    ? "Enable full keyboard access to copy/paste images."
                    : "File copied to your clipboard. Paste to use it.",
                style: .style(
                    backgroundColor: Color(.tertiarySystemBackground),
                    titleColor: .primary,
                    titleFont: .custom("IBMPlexMono-Medium", size: 14)
                )
            )
        }
        .toast(isPresenting: $showCreatedToast) {
            AlertToast(
                displayMode: .banner(.pop),
                type: .systemImage("checkmark.circle.fill", .green),
                title: "New Snippet created!",
                style: .style(
                    backgroundColor: Color(.tertiarySystemBackground),
                    titleColor: .primary,
                    titleFont: .custom("IBMPlexMono-Medium", size: 14)
                )
            )
        }
    }

    // MARK: - Toolbar

    @ViewBuilder
    private func ToolbarView() -> some View {
        HStack(spacing: 16) {
            // Sort menu — icon only
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
                        Label("Earliest First", systemImage: "arrow.up").tag(SortOrder.forward)
                        Label("Latest First", systemImage: "arrow.down").tag(SortOrder.reverse)
                    case .recentlyUsed:
                        Label("Most Recent First", systemImage: "arrow.up").tag(SortOrder.reverse)
                        Label("Least Recent First", systemImage: "arrow.down").tag(SortOrder.forward)
                    case .alphabetical:
                        Label("A to Z", systemImage: "arrow.up").tag(SortOrder.forward)
                        Label("Z to A", systemImage: "arrow.down").tag(SortOrder.reverse)
                    }
                }
            } label: {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color(.secondaryLabel))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }

            // Tag filter menu
            if !tags.isEmpty {
                TagFilterMenu()
            } else {
                Text("Add tags for quick search")
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(Color(.tertiaryLabel))
            }

            // Clear filter
            if selectedFilter != nil {
                Button {
                    selectedFilter = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Color(.tertiaryLabel))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            // Vault lock indicator — icon only, shown when secure snippets exist
            if snippets.contains(where: { $0.isSecure }) {
                Image(systemName: isUnlocked ? "lock.open" : "lock")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color(.secondaryLabel))
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 0)
    }

    // MARK: - Create Snippet CTA

    @ViewBuilder
    private func CreateSnippetCTA() -> some View {
        if showCreateSnippetCTA {
            if checkFullAccess() {
                Button {
                    createNewSnippetFromKeyboard(content: selectedText)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 14, weight: .medium))
                        Text("Save as snippet")
                            .font(.custom("IBMPlexMono-Medium", size: 12))
                    }
                    .foregroundStyle(Color(.label))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color(.secondarySystemBackground))
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.top, 4)
                .padding(.bottom, 4)
                .transition(.scale.combined(with: .opacity))
                .animation(.easeInOut(duration: 0.2), value: showCreateSnippetCTA)
            } else {
                Text("Enable Full Access to create snippets from selected text.")
                    .foregroundStyle(Color(.tertiaryLabel))
                    .font(.system(size: 11))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 4)
            }
        }
    }

    // MARK: - Bottom Bar

    @ViewBuilder
    private func BottomBar() -> some View {
        HStack(spacing: 8) {
            // Back to keyboard
            if let qState = qwertyStateFromEnvironment {
                Button {
                    if currentKeyboardSettings.isQWERTYKeyboardEnabled {
                        qState.showingSnippets = false
                    } else {
                        keyboardActions.advanceToNextInputMode()
                    }
                } label: {
                    HStack() {
                        Image(systemName: "keyboard")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color(.secondaryLabel))
                            .frame(width: 44, height: 32)
                            .contentShape(Rectangle())
                        Text("Switch to keyboard")
                            .underline()
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color(.secondaryLabel))
                    }
                    .foregroundStyle(selectedFilter != nil ? Color(.label) : Color(.secondaryLabel))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color(.secondarySystemBackground))
                    )
                  
                    
                }
            } else {
                // Legacy fallback: switch to next system keyboard
                Button {
                    NotificationCenter.default.post(
                        name: NSNotification.Name(rawValue: "switchKey"), object: nil)
                } label: {
                    Image(systemName: "keyboard")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Color(.secondaryLabel))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
            }

            Spacer()

            // Action buttons
            ActionButtons()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    // MARK: - Tag Filter Menu

    @ViewBuilder
    private func TagFilterMenu() -> some View {
        Menu {
            ForEach(tags, id: \.id) { tag in
                Button {
                    selectedFilter = tag
                } label: {
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
                            Image(systemName: tag.imageTag ?? "tag")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                if let filter = selectedFilter, let colorHex = filter.colorHex {
                    TagColorIndicator(colorHex: colorHex, size: 6)
                }
                Image(systemName: selectedFilter?.imageTag ?? "line.3.horizontal.decrease.circle")
                    .font(.system(size: 13))
                Text(selectedFilter?.name ?? "Filter")
                    .font(.system(size: 12))
            }
            .foregroundStyle(selectedFilter != nil ? Color(.label) : Color(.secondaryLabel))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(.secondarySystemBackground))
            )
        }
    }

    // MARK: - Action Buttons

    @ViewBuilder
    private func ActionButtons() -> some View {
        HStack(spacing: 6) {
            // Space
            Button { spaceAction() } label: {
                Image(systemName: "space")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 24, height: 14)
                    .foregroundStyle(Color(.label))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color(.secondarySystemBackground))
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Return
            Button { returnAction() } label: {
                Image(systemName: "return")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 18, height: 14)
                    .foregroundStyle(Color(.label))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color(.secondarySystemBackground))
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Delete (with long-press for rapid deletion)
            Button {
                deleteCharacter(isLongPress: false)
            } label: {
                Image(systemName: "delete.left")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 18, height: 14)
                    .foregroundStyle(Color(.label))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color(.secondarySystemBackground))
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
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
    }

    // MARK: - Snippet Actions

    private func sentValue(snippet: SnippetItem) {
        snippetViewModel.trackSnippetUsage(snippet: snippet)

        if snippet.isSecure {
            sentSecureValue(snippet: snippet)
        } else {
            sentValueToKeyboard(snippet: snippet)
        }
    }

    private func sentSecureValue(snippet: SnippetItem) {
        deviceBiometrics.authenticate(
            successHandler: {
                isUnlocked = true
                sentValueToKeyboard(snippet: snippet)
            },
            unSuccessHandler: { _ in
                isUnlocked = false
            }
        )
    }

    private func sentValueToKeyboard(snippet: SnippetItem) {
        NotificationCenter.default.post(
            name: NSNotification.Name(rawValue: "addKey"), object: snippet)

        if snippet.type == .image || snippet.type == .file {
            showToast = true
        } else {
            actionKeyboardAfterPaste(actionKey: currentKeyboardSettings.afterPasteAction)
        }
    }

    private func actionKeyboardAfterPaste(actionKey: KeyboardAfterPasteAction) {
        switch actionKey {
        case .rtrn:
            NotificationCenter.default.post(
                name: NSNotification.Name(rawValue: "addKey"), object: String(UnicodeScalar(0x000D)!))
            NotificationCenter.default.post(
                name: NSNotification.Name(rawValue: "addKey"), object: String(UnicodeScalar(0x000D)!))
        case .changeReturn:
            NotificationCenter.default.post(
                name: NSNotification.Name(rawValue: "addKey"), object: String(UnicodeScalar(0x000D)!))
            NotificationCenter.default.post(
                name: NSNotification.Name(rawValue: "addKey"), object: String(UnicodeScalar(0x000D)!))
            NotificationCenter.default.post(
                name: NSNotification.Name(rawValue: "switchKey"), object: nil)
        case .change:
            NotificationCenter.default.post(
                name: NSNotification.Name(rawValue: "addKey"), object: String(UnicodeScalar(0x0020)!))
            NotificationCenter.default.post(
                name: NSNotification.Name(rawValue: "switchKey"), object: nil)
        case .space:
            NotificationCenter.default.post(
                name: NSNotification.Name(rawValue: "addKey"), object: String(UnicodeScalar(0x0020)!))
        case .nothing:
            break
        }
    }

    // MARK: - Keyboard Actions

    private func deleteCharacter(isLongPress: Bool) {
        NotificationCenter.default.post(
            name: NSNotification.Name(rawValue: "deleteKey"), object: isLongPress)
    }

    private func spaceAction() {
        NotificationCenter.default.post(
            name: NSNotification.Name(rawValue: "addKey"), object: String(UnicodeScalar(0x0020)!))
    }

    private func returnAction() {
        NotificationCenter.default.post(
            name: NSNotification.Name(rawValue: "addKey"), object: String(UnicodeScalar(0x000D)!))
    }

    private func startRapidDeletion() {
        deleteTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            deleteCharacter(isLongPress: true)
        }
    }

    private func stopRapidDeletion() {
        isLongPressing = false
        deleteTimer?.invalidate()
        deleteTimer = nil
    }

    // MARK: - Create Snippet

    private func createNewSnippetFromKeyboard(content: String) {
        let title = String(content.prefix(14))
        snippetViewModel.createSnippet(title, content: content, type: .txt, isSecure: false)
        showCreatedToast = true
    }

    // MARK: - Notification Observers

    private func setupNotificationObservers() {
        removeNotificationObservers()

        let o1 = NotificationCenter.default.addObserver(
            forName: NSNotification.Name(rawValue: "selectText"),
            object: nil, queue: nil
        ) { notification in
            if let text = notification.object as? String, !text.isEmpty {
                showCreateSnippetCTA = true
                selectedText = text
            }
        }

        let o2 = NotificationCenter.default.addObserver(
            forName: NSNotification.Name(rawValue: "selectTextEmpty"),
            object: nil, queue: nil
        ) { _ in
            showCreateSnippetCTA = false
        }

        notificationObservers = [o1, o2]
    }

    private func removeNotificationObservers() {
        for observer in notificationObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        notificationObservers.removeAll()
    }
}

// MARK: - Keyboard View Extension (Root Entry Point)

struct KeyboardViewExt: View {
    @State private var container: ModelContainer?
    @State private var settingsViewModel: SettingsViewModel?

    var qwertyState: QWERTYKeyboardState
    var keyboardActions: KeyboardActions
    var slashCommandState: SlashCommandState
    var predictiveTextState: PredictiveTextState
    var reminderSuggestionState: ReminderSuggestionState

    var body: some View {
        Group {
            if let container = container, let settingsViewModel = settingsViewModel {
                Group {
                    if qwertyState.showingSnippets {
                        KeyboardView()
                    } else if AppGroupSettings.bool(forKey: AppGroupSettings.Key.useNativeKeyboardV2, default: true) {
                        // V2 (experimental) — single-root gesture, finger-slide, accents, space cursor.
                        NativeKeyboardV2View_SwiftUI(adjustCaret: keyboardActions.adjustCaret)
                    } else {
                        // V1 — original per-key UIControl implementation.
                        QWERTYKeyboardView()
                    }
                }
                .modelContainer(container)
                .environment(settingsViewModel)
                .environment(qwertyState)
                .environment(\.keyboardActions, keyboardActions)
                .environment(\.slashCommandState, slashCommandState)
                .environment(\.predictiveTextState, predictiveTextState)
                .environment(\.reminderSuggestionState, reminderSuggestionState)
            } else {
                // Reserve the full keyboard rect so the system shows the keyboard
                // frame instantly. No ProgressView — it would draw and animate,
                // adding visible jitter while SwiftData is still opening.
                Color.clear
                    .frame(height: KeyboardDimensions.totalHeight(forScreenWidth: UIScreen.main.bounds.width))
            }
        }
        .task {
            await loadIfNeeded()
        }
    }

    private func loadIfNeeded() async {
        guard container == nil else { return }
        let loaded = await ModelContainerProvider.shared.get()
        let modelContext = loaded.mainContext
        let viewModel = SettingsViewModel(modelContext: modelContext)

        // Read the experimental QWERTY keyboard setting to determine initial view.
        let isQWERTYEnabled = fetchQWERTYKeyboardSetting(from: modelContext)
        qwertyState.showingSnippets = !isQWERTYEnabled

        container = loaded
        settingsViewModel = viewModel
    }

    private func fetchQWERTYKeyboardSetting(from context: ModelContext) -> Bool {
        let descriptor = FetchDescriptor<SettingsModel>()
        do {
            let settings = try context.fetch(descriptor)
            return settings.first?.isQWERTYKeyboardEnabled ?? false
        } catch {
            return false
        }
    }
}

// MARK: - Preview

#Preview {
    let tempSettingsContainer = SnipKeyDataManager().makeSharedContainer()
    let settingsViewModel = SettingsViewModel(modelContext: tempSettingsContainer.mainContext)

    return KeyboardViewExt(
        qwertyState: QWERTYKeyboardState(),
        keyboardActions: KeyboardActions.noop,
        slashCommandState: SlashCommandState(),
        predictiveTextState: PredictiveTextState(),
        reminderSuggestionState: ReminderSuggestionState()
    )
    .onAppear {
        settingsViewModel.modelContext = tempSettingsContainer.mainContext
        settingsViewModel.setupKeyboardSettings()
    }
    .modelContainer(tempSettingsContainer)
    .environment(settingsViewModel)
}
