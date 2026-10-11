import UIKit
import Observation

@MainActor
final class EmojiKeyboardView: UIView, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    static let searchAdditionalHeight = EmojiSurfaceGeometry.searchAdditionalHeight
    private static let catalogTask = Task.detached(priority: .userInitiated) { () throws -> EmojiCatalog in
        try EmojiCatalog.loadBundled()
    }

    private let actions: KeyboardActions
    private let onReturnToTyping: () -> Void
    private let onSearchModeChanged: (Bool) -> Void
    private let recents = EmojiRecentsStore()
    private var catalog: EmojiCatalog?
    private var isDark = false
    private var selectedGroup = 0 // Section zero is Recents.
    private var browseSections: [[Int]] = []
    private var isAdjustingBrowseLayout = false
    private var matchIndices: [Int] = []
    private var isSearching = false
    private var query = EmojiSearchQuery()
    private var lastSearchedText: String?
    private var searchWorker: Task<[Int], Never>?
    private var deleteTimer: Timer?
    private var variantPicker: EmojiVariantPicker?

    private let grid: UICollectionView
    private let browseLayout: EmojiBrowseLayout
    private let matches: UICollectionView
    private let searchField = EmojiSearchField()
    private let abcButton = UIButton(type: .system)
    private let deleteButton = EmojiDeleteButton(type: .system)
    private var categoryButtons: [EmojiCategoryButton] = []
    private let statusLabel = UILabel()
    private let matchStatusLabel = UILabel()
    private let localState = QWERTYKeyboardState()
    private var searchKeyboard: NativeKeyboardV2View?
    private let localCallout = KeyboardCalloutView()

    init(actions: KeyboardActions, onReturnToTyping: @escaping () -> Void,
         onSearchModeChanged: @escaping (Bool) -> Void) {
        self.actions = actions
        self.onReturnToTyping = onReturnToTyping
        self.onSearchModeChanged = onSearchModeChanged
        browseLayout = EmojiBrowseLayout()
        grid = UICollectionView(frame: .zero, collectionViewLayout: browseLayout)
        let matchLayout = UICollectionViewFlowLayout()
        matchLayout.scrollDirection = .horizontal
        matchLayout.minimumLineSpacing = 0
        matchLayout.minimumInteritemSpacing = 0
        matches = UICollectionView(frame: .zero, collectionViewLayout: matchLayout)
        super.init(frame: .zero)
        configureViews()
        localState.surface = .typing
        localState.layoutProfile = .emojiSearch
        localState.needsInputModeSwitchKey = false
        localState.returnKeyLabel = "Done"
        localState.returnKeyIsProminent = true
        observeLocalSurface()
        Task { @MainActor [weak self] in
            do {
                let loaded = try await Self.catalogTask.value
                self?.install(loaded)
            } catch {
                self?.statusLabel.text = "Emoji data unavailable"
                self?.statusLabel.isHidden = false
                self?.searchField.isEnabled = false
            }
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    /// Safe for both presentation and host appearance changes: a live local query
    /// is preserved, and only visible cells are refreshed when the palette changes.
    func prepareForPresentation(isDark: Bool) {
        let changedAppearance = self.isDark != isDark
        self.isDark = isDark
        overrideUserInterfaceStyle = isDark ? .dark : .light
        localState.appearanceMode = isDark ? .dark : .light
        recents.reload(allowSharedAccess: actions.hasFullAccess())
        if catalog != nil, !isSearching { updateBrowseItems() }
        applyAppearance()
        if changedAppearance {
            dismissVariants()
            refreshVisibleCells(in: grid)
            refreshVisibleCells(in: matches)
        }
    }

    func cancelInteraction() {
        stopDeleting()
        searchKeyboard?.cancelActiveInteraction()
        dismissVariants()
        grid.setContentOffset(grid.contentOffset, animated: false)
        matches.setContentOffset(matches.contentOffset, animated: false)
    }

    private func configureViews() {
        backgroundColor = .clear
        for collection in [grid, matches] {
            collection.backgroundColor = .clear
            collection.dataSource = self
            collection.delegate = self
            collection.showsHorizontalScrollIndicator = false
            collection.alwaysBounceHorizontal = true
            collection.alwaysBounceVertical = false
            collection.showsVerticalScrollIndicator = false
            collection.contentInsetAdjustmentBehavior = .never
            collection.isDirectionalLockEnabled = true
            collection.register(EmojiCollectionCell.self, forCellWithReuseIdentifier: EmojiCollectionCell.reuseIdentifier)
            let longPress = UILongPressGestureRecognizer(target: self, action: #selector(holdEmoji(_:)))
            longPress.minimumPressDuration = 0.4
            collection.addGestureRecognizer(longPress)
            addSubview(collection)
        }
        matches.isHidden = true
        searchField.onBeginEditing = { [weak self] in self?.searchTapped() }
        searchField.onSetCaret = { [weak self] in
            self?.query.setCaret(to: $0)
            self?.queryCaretDidChange()
        }
        searchField.onClear = { [weak self] in
            self?.query.clear()
            self?.queryDidChange()
        }
        addSubview(searchField)
        abcButton.setTitle("ABC", for: .normal)
        abcButton.titleLabel?.font = .systemFont(ofSize: 16)
        abcButton.accessibilityLabel = "Return to typing"
        abcButton.addTarget(self, action: #selector(returnToTyping), for: .touchUpInside)
        addSubview(abcButton)
        deleteButton.setImage(UIImage(systemName: "delete.left"), for: .normal)
        deleteButton.accessibilityLabel = "Delete backward"
        deleteButton.addTarget(self, action: #selector(beginDeleting), for: .touchDown)
        deleteButton.addTarget(self, action: #selector(stopDeleting), for: [.touchUpInside, .touchUpOutside, .touchCancel, .touchDragExit])
        addSubview(deleteButton)
        deleteButton.setPreferredSymbolConfiguration(UIImage.SymbolConfiguration(pointSize: 22), forImageIn: .normal)
        statusLabel.text = "Loading emoji…"
        statusLabel.font = .systemFont(ofSize: 14)
        statusLabel.numberOfLines = 0
        statusLabel.textAlignment = .center
        statusLabel.isUserInteractionEnabled = false
        addSubview(statusLabel)
        matchStatusLabel.font = .systemFont(ofSize: 14)
        matchStatusLabel.textAlignment = .center
        matchStatusLabel.numberOfLines = 2
        matchStatusLabel.isUserInteractionEnabled = false
        matchStatusLabel.isHidden = true
        addSubview(matchStatusLabel)
        localCallout.isUserInteractionEnabled = false
        addSubview(localCallout)
        updateSearchField()
        applyAppearance()
    }

    private func install(_ catalog: EmojiCatalog) {
        self.catalog = catalog
        recents.reload(allowSharedAccess: actions.hasFullAccess())
        selectedGroup = recents.sequences.contains(where: { catalog.indexByText[$0] != nil }) ? 0 : 1
        let names = ["Recents"] + catalog.browseGroups.map(\.name)
        let symbols = ["clock"] + catalog.browseGroups.map(\.symbol)
        for index in names.indices {
            let button = EmojiCategoryButton(frame: .zero)
            button.tag = index
            button.setImage(UIImage(systemName: symbols[index]), for: .normal)
            button.accessibilityLabel = names[index]
            button.addTarget(self, action: #selector(selectCategory(_:)), for: .touchUpInside)
            addSubview(button)
            categoryButtons.append(button)
        }
        searchField.isEnabled = true
        updateBrowseItems()
        layoutIfNeeded()
        scrollToCategory(selectedGroup, animated: false)
        applyAppearance()
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let dims = KeyboardDimensions(screenWidth: bounds.width)
        let frames = EmojiSurfaceGeometry(size: bounds.size, headerHeight: dims.toolbarHeight,
                                          keysHeight: dims.keysAreaHeight, categoryCount: categoryButtons.count)
        searchField.frame = frames.search
        if isSearching {
            if matches.frame != frames.results {
                matches.frame = frames.results
                matches.collectionViewLayout.invalidateLayout()
            }
            matchStatusLabel.frame = frames.results
            searchKeyboard?.frame = frames.keys
        } else {
            isAdjustingBrowseLayout = true
            let changedSize = grid.bounds.size != frames.browse.size
            if grid.frame != frames.browse { grid.frame = frames.browse }
            if changedSize {
                browseLayout.invalidateLayout()
                grid.layoutIfNeeded()
                scrollToCategory(selectedGroup, animated: false)
            }
            isAdjustingBrowseLayout = false
            statusLabel.frame = frames.browse.insetBy(dx: 20, dy: 0)
            abcButton.frame = frames.abc
            deleteButton.frame = frames.delete
            for (index, button) in categoryButtons.enumerated() {
                button.frame = frames.categories[index]
            }
        }
        // KeyboardCalloutView owns its balloon frame; resizing it here races the
        // pressed-key presentation and causes flashes on every query/layout update.
        variantPicker?.frame = bounds
    }

    private func applyAppearance() {
        let foreground: UIColor = isDark ? .white : .black
        let selectedColor = foreground.withAlphaComponent(isDark ? 0.12 : 0.10)
        searchField.backgroundColor = foreground.withAlphaComponent(isDark ? 0.09 : 0.07)
        abcButton.tintColor = foreground
        deleteButton.tintColor = foreground
        statusLabel.textColor = .secondaryLabel
        matchStatusLabel.textColor = .secondaryLabel
        for button in categoryButtons {
            let selected = button.tag == selectedGroup
            button.isSelected = selected
            button.tintColor = foreground.withAlphaComponent(selected ? 1 : 0.72)
            button.setSelectionColor(selectedColor)
            button.accessibilityTraits = selected ? [.button, .selected] : .button
        }
    }

    @objc private func selectCategory(_ sender: UIButton) {
        dismissVariants()
        updateBrowseItems()
        selectedGroup = sender.tag
        scrollToCategory(selectedGroup, animated: !UIAccessibility.isReduceMotionEnabled)
        updateBrowseStatus()
        applyAppearance()
    }

    private func updateBrowseItems() {
        guard let catalog else { return }
        let recentIndices = recents.sequences.compactMap { catalog.indexByText[$0] }
        if browseSections.isEmpty {
            browseSections = [recentIndices] + catalog.browseGroups.map(\.entries)
        } else {
            guard browseSections[0] != recentIndices else { return }
            browseSections[0] = recentIndices
        }
        isAdjustingBrowseLayout = true
        defer { isAdjustingBrowseLayout = false }
        let previousOffset = browseLayout.geometry.sectionOffsets.indices.contains(selectedGroup)
            ? grid.contentOffset.x - browseLayout.geometry.sectionOffsets[selectedGroup] : 0
        browseLayout.itemCounts = browseSections.map(\.count)
        grid.reloadData()
        grid.layoutIfNeeded()
        if browseLayout.geometry.sectionOffsets.indices.contains(selectedGroup) {
            let x = browseLayout.geometry.offset(forSection: selectedGroup) + max(0, previousOffset)
            grid.setContentOffset(CGPoint(x: min(x, max(0, grid.contentSize.width - grid.bounds.width)), y: 0), animated: false)
        }
        updateBrowseStatus()
    }

    private func scrollToCategory(_ section: Int, animated: Bool) {
        grid.layoutIfNeeded()
        guard browseLayout.geometry.sectionOffsets.indices.contains(section) else { return }
        grid.setContentOffset(CGPoint(x: browseLayout.geometry.offset(forSection: section), y: 0), animated: animated)
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard scrollView === grid, !isSearching, !isAdjustingBrowseLayout,
              let section = browseLayout.geometry.section(atOffset: grid.contentOffset.x),
              section != selectedGroup else { return }
        selectedGroup = section
        updateBrowseStatus()
        applyAppearance()
    }

    private func updateBrowseStatus() {
        statusLabel.text = "Recently used emoji appear here"
        statusLabel.isHidden = isSearching || selectedGroup != 0 || !(browseSections.first?.isEmpty ?? true)
    }

    private func refreshVisibleCells(in collection: UICollectionView) {
        for path in collection.indexPathsForVisibleItems {
            guard let cell = collection.cellForItem(at: path) as? EmojiCollectionCell else { continue }
            configure(cell, in: collection, at: path)
        }
    }

    private func selectEmoji(_ index: Int) {
        guard let catalog else { return }
        let text = catalog.entries[index].text
        actions.insertText(text)
        actions.scheduleSideEffects()
        recents.record(text)
        dismissVariants()
        // Keep a visible recents grid stable under repeated taps. Refresh on the
        // next category selection/presentation rather than moving the tapped item.
    }

    func numberOfSections(in collectionView: UICollectionView) -> Int {
        collectionView === grid ? browseSections.count : 1
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        collectionView === grid ? browseSections[section].count : matchIndices.count
    }

    private func entryIndex(in collection: UICollectionView, at indexPath: IndexPath) -> Int {
        collection === grid ? browseSections[indexPath.section][indexPath.item] : matchIndices[indexPath.item]
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: EmojiCollectionCell.reuseIdentifier, for: indexPath) as! EmojiCollectionCell
        configure(cell, in: collectionView, at: indexPath)
        return cell
    }

    private func configure(_ cell: EmojiCollectionCell, in collectionView: UICollectionView, at indexPath: IndexPath) {
        guard let catalog else { return }
        let index = entryIndex(in: collectionView, at: indexPath)
        let entry = catalog.entries[index]
        let hasVariants = !catalog.entries[entry.base].variants.isEmpty
        let chooseVariant: (() -> Void)? = hasVariants ? { [weak self] in self?.showVariants(for: index) } : nil
        cell.configure(entry: entry, hasVariants: hasVariants, isDark: isDark, chooseVariant: chooseVariant)
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout,
                        sizeForItemAt indexPath: IndexPath) -> CGSize {
        CGSize(width: max(44, collectionView.bounds.width / CGFloat(max(1, Int(collectionView.bounds.width / 48)))),
               height: Self.searchAdditionalHeight)
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        selectEmoji(entryIndex(in: collectionView, at: indexPath))
    }

    @objc private func holdEmoji(_ recognizer: UILongPressGestureRecognizer) {
        guard recognizer.state == .began, let collection = recognizer.view as? UICollectionView,
              let path = collection.indexPathForItem(at: recognizer.location(in: collection)) else { return }
        showVariants(for: entryIndex(in: collection, at: path))
    }

    private func showVariants(for index: Int) {
        guard let catalog else { return }
        let base = catalog.entries[index].base
        guard !catalog.entries[base].variants.isEmpty else { return }
        stopDeleting()
        searchKeyboard?.cancelActiveInteraction()
        dismissVariants()
        let picker = EmojiVariantPicker(catalog: catalog, base: base, isDark: isDark,
                                        onSelect: { [weak self] in self?.selectEmoji($0) },
                                        onDismiss: { [weak self] in self?.dismissVariants() })
        variantPicker = picker
        picker.frame = bounds
        addSubview(picker)
        UIAccessibility.post(notification: .screenChanged, argument: picker)
    }

    private func dismissVariants() {
        guard let picker = variantPicker else { return }
        picker.removeFromSuperview()
        variantPicker = nil
        UIAccessibility.post(notification: .layoutChanged, argument: isSearching ? matches : grid)
    }

    @objc private func beginDeleting() {
        stopDeleting()
        deleteOnce()
        deleteTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.deleteOnce()
                self.deleteTimer = Timer.scheduledTimer(withTimeInterval: 0.085, repeats: true) { [weak self] _ in
                    MainActor.assumeIsolated { self?.deleteOnce() }
                }
            }
        }
    }

    @objc private func stopDeleting() {
        deleteTimer?.invalidate()
        deleteTimer = nil
    }

    private func deleteOnce() {
        actions.deleteBackward()
        actions.scheduleSideEffects()
    }

    @objc private func returnToTyping() {
        cancelInteraction()
        onReturnToTyping()
    }

    @objc private func searchTapped() {
        guard !isSearching, catalog != nil else { return }
        cancelInteraction()
        isSearching = true
        localState.surface = .typing
        localState.currentPage = .letters
        localState.shiftState = .disabled
        localState.inputTracking.resetAutoPeriodTracking()
        if searchKeyboard == nil {
            let keyboard = NativeKeyboardV2View(state: localState, actions: makeSearchActions())
            keyboard.setCaretAdjustment { [weak self] offset in self?.moveQueryCaret(by: offset) }
            searchKeyboard = keyboard
            insertSubview(keyboard, belowSubview: localCallout)
        }
        updateSearchVisibility()
        refreshSearch()
        onSearchModeChanged(true)
        UIAccessibility.post(notification: .layoutChanged, argument: searchField)
    }

    @objc private func endSearch() {
        guard isSearching else { return }
        cancelInteraction()
        isSearching = false
        searchWorker?.cancel()
        searchWorker = nil
        query.clear()
        lastSearchedText = nil
        localState.surface = .typing
        localState.inputTracking.contextMirror.reset(to: nil)
        updateBrowseItems()
        updateSearchVisibility()
        onSearchModeChanged(false)
        UIAccessibility.post(notification: .layoutChanged, argument: searchField)
    }

    private func updateSearchVisibility() {
        grid.isHidden = isSearching
        categoryButtons.forEach { $0.isHidden = isSearching }
        abcButton.isHidden = isSearching
        deleteButton.isHidden = isSearching
        matches.isHidden = !isSearching
        searchKeyboard?.isHidden = !isSearching
        updateBrowseStatus()
        matchStatusLabel.isHidden = !isSearching || !matchIndices.isEmpty
        updateSearchField()
        setNeedsLayout()
    }

    private func updateSearchField() {
        searchField.update(text: query.text, caret: query.caret, isEditing: isSearching)
    }

    private func refreshSearch() {
        guard let catalog, isSearching, lastSearchedText != query.text else { return }
        let text = query.text
        lastSearchedText = text
        searchWorker?.cancel()
        searchWorker = nil
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let recentIndices = recents.sequences.compactMap { catalog.indexByText[$0] }
            applyMatches(recentIndices.isEmpty ? Array(catalog.browseGroups[0].entries.prefix(40)) : recentIndices)
            return
        }
        let worker = Task.detached(priority: .userInitiated) { catalog.search(text) }
        searchWorker = worker
        Task { @MainActor [weak self] in
            let indices = await worker.value
            guard !worker.isCancelled, let self, self.isSearching, self.query.text == text else { return }
            self.applyMatches(indices)
        }
    }

    private func applyMatches(_ indices: [Int]) {
        if matchIndices != indices {
            matchIndices = indices
            matches.reloadData()
            matches.setContentOffset(.zero, animated: false)
        }
        matchStatusLabel.text = "No matches"
        matchStatusLabel.isHidden = !isSearching || !matchIndices.isEmpty
    }

    private func queryDidChange() {
        queryCaretDidChange()
        refreshSearch()
    }

    private func moveQueryCaret(by offset: Int) {
        query.moveCaret(by: offset)
        queryCaretDidChange()
    }

    private func queryCaretDidChange() {
        localState.inputTracking.contextMirror.reset(to: query.contextBeforeInput)
        updateSearchField()
    }

    private func observeLocalSurface() {
        withObservationTracking {
            _ = localState.surface
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if self.localState.surface != .typing { self.endSearch() }
                self.observeLocalSurface()
            }
        }
    }

    /// Explicitly isolated from the host actions. Even Return, accelerated deletion,
    /// long-press accents, and caret dragging can only affect the local query.
    private func makeSearchActions() -> KeyboardActions {
        let traits = HostInputTraits(
            keyboardType: .asciiCapable, keyboardAppearance: .default, returnKeyType: .done,
            autocapitalizationType: .none, autocorrectionType: .no, spellCheckingType: .no,
            smartQuotesEnabled: false, smartDashesEnabled: false, autoCapitalizationEnabled: false,
            needsInputModeSwitchKey: false, localeCodes: []
        )
        return KeyboardActions(
            insertText: { [weak self] text in
                guard let self else { return }
                if text == "\n" { self.endSearch(); return }
                self.query.insert(text)
                self.queryDidChange()
            },
            deleteBackward: { [weak self] in
                self?.query.deleteBackward()
                self?.queryDidChange()
            },
            advanceToNextInputMode: {},
            documentContextBeforeInput: { [weak self] in self?.query.contextBeforeInput },
            screenWidthProvider: { [weak self] in self?.bounds.width ?? 393 },
            openApp: {}, hasFullAccess: { false },
            createReminder: { _, _ in }, createTimer: { _, _ in }, pasteFromClipboard: {},
            copySnippetFile: { _ in .noFullAccess }, evaluateSlashCommand: {}, evaluatePredictiveText: {},
            scheduleSideEffects: { [weak self] in
                // Search spaces are literal; double-space must not become a period.
                self?.localState.inputTracking.resetAutoPeriodTracking()
                self?.refreshSearch()
            },
            adjustCaret: { [weak self] in self?.moveQueryCaret(by: $0) },
            inputTraits: { traits }, activeInputLocaleCodes: { [] },
            insertQuickCommand: { _ in },
            acceptPredictiveCandidate: { _ in }, showSwipeAlternatives: { _, _ in },
            v2CalloutView: localCallout
        )
    }

    override func accessibilityPerformEscape() -> Bool {
        if variantPicker != nil { dismissVariants() }
        else if isSearching { endSearch() }
        else { returnToTyping() }
        return true
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { cancelInteraction() }
    }
}
