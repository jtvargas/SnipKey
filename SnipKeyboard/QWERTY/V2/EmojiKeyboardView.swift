import UIKit
import Observation

@MainActor
final class EmojiKeyboardView: UIView, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    private static let catalogTask = Task.detached(priority: .userInitiated) { () throws -> EmojiCatalog in
        guard let url = Bundle.main.url(forResource: "emoji-en", withExtension: "plist") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try EmojiCatalog.load(from: url)
    }

    private let actions: KeyboardActions
    private let onReturnToTyping: () -> Void
    private let recents = EmojiRecentsStore()
    private var catalog: EmojiCatalog?
    private var isDark = false
    private var selectedGroup = 0 // -1 is Recents.
    private var browseIndices: [Int] = []
    private var matchIndices: [Int] = []
    private var isSearching = false
    private var query = EmojiSearchQuery()
    private var lastSearchedText: String?
    private var deleteTimer: Timer?
    private var variantPicker: EmojiVariantPicker?

    private let grid: UICollectionView
    private let matches: UICollectionView
    private let searchButton = UIButton(type: .system)
    private let cancelButton = UIButton(type: .system)
    private let abcButton = UIButton(type: .system)
    private let deleteButton = EmojiDeleteButton(type: .system)
    private let categoryScroll = UIScrollView()
    private var categoryButtons: [UIButton] = []
    private let statusLabel = UILabel()
    private let matchStatusLabel = UILabel()
    private let localState = QWERTYKeyboardState()
    private var searchKeyboard: NativeKeyboardV2View?
    private let localCallout = KeyboardCalloutView()

    init(actions: KeyboardActions, onReturnToTyping: @escaping () -> Void) {
        self.actions = actions
        self.onReturnToTyping = onReturnToTyping
        let gridLayout = UICollectionViewFlowLayout()
        gridLayout.minimumLineSpacing = 0
        gridLayout.minimumInteritemSpacing = 0
        gridLayout.sectionInset = UIEdgeInsets(top: 2, left: 4, bottom: 2, right: 4)
        grid = UICollectionView(frame: .zero, collectionViewLayout: gridLayout)
        let matchLayout = UICollectionViewFlowLayout()
        matchLayout.scrollDirection = .horizontal
        matchLayout.minimumLineSpacing = 0
        matchLayout.minimumInteritemSpacing = 0
        matches = UICollectionView(frame: .zero, collectionViewLayout: matchLayout)
        super.init(frame: .zero)
        configureViews()
        localState.surface = .typing
        localState.layoutProfile = .asciiCapable
        localState.needsInputModeSwitchKey = false
        localState.returnKeyLabel = "Done"
        observeLocalSurface()
        Task { @MainActor [weak self] in
            do {
                let loaded = try await Self.catalogTask.value
                self?.install(loaded)
            } catch {
                self?.statusLabel.text = "Emoji data unavailable"
                self?.statusLabel.isHidden = false
                self?.searchButton.isEnabled = false
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
        if catalog != nil, selectedGroup == -1, !isSearching { updateBrowseItems() }
        applyAppearance()
        if changedAppearance {
            dismissVariants()
            grid.reloadData()
            matches.reloadData()
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
            collection.alwaysBounceVertical = collection === grid
            collection.register(EmojiCollectionCell.self, forCellWithReuseIdentifier: EmojiCollectionCell.reuseIdentifier)
            let longPress = UILongPressGestureRecognizer(target: self, action: #selector(holdEmoji(_:)))
            longPress.minimumPressDuration = 0.4
            collection.addGestureRecognizer(longPress)
            addSubview(collection)
        }
        matches.isHidden = true
        searchButton.contentHorizontalAlignment = .leading
        searchButton.setImage(UIImage(systemName: "magnifyingglass"), for: .normal)
        searchButton.titleLabel?.font = UIFont(name: "IBMPlexMono-Regular", size: 13) ?? .systemFont(ofSize: 13)
        searchButton.titleLabel?.lineBreakMode = .byTruncatingMiddle
        searchButton.layer.cornerRadius = 7
        searchButton.addTarget(self, action: #selector(searchTapped), for: .touchUpInside)
        searchButton.accessibilityLabel = "Search emoji"
        searchButton.isEnabled = false
        addSubview(searchButton)
        cancelButton.setTitle("Cancel", for: .normal)
        cancelButton.titleLabel?.font = UIFont(name: "IBMPlexMono-Medium", size: 12) ?? .systemFont(ofSize: 12, weight: .medium)
        cancelButton.addTarget(self, action: #selector(endSearch), for: .touchUpInside)
        cancelButton.isHidden = true
        addSubview(cancelButton)
        abcButton.setTitle("ABC", for: .normal)
        abcButton.titleLabel?.font = .systemFont(ofSize: 16)
        abcButton.accessibilityLabel = "Return to typing"
        abcButton.addTarget(self, action: #selector(returnToTyping), for: .touchUpInside)
        abcButton.layer.cornerRadius = 7
        addSubview(abcButton)
        deleteButton.setImage(UIImage(systemName: "delete.left"), for: .normal)
        deleteButton.accessibilityLabel = "Delete backward"
        deleteButton.layer.cornerRadius = 7
        deleteButton.addTarget(self, action: #selector(beginDeleting), for: .touchDown)
        deleteButton.addTarget(self, action: #selector(stopDeleting), for: [.touchUpInside, .touchUpOutside, .touchCancel, .touchDragExit])
        addSubview(deleteButton)
        categoryScroll.showsHorizontalScrollIndicator = false
        categoryScroll.accessibilityLabel = "Emoji categories"
        addSubview(categoryScroll)
        statusLabel.text = "Loading emoji…"
        statusLabel.font = UIFont(name: "IBMPlexMono-Regular", size: 13) ?? .systemFont(ofSize: 13)
        statusLabel.numberOfLines = 0
        statusLabel.textAlignment = .center
        statusLabel.isUserInteractionEnabled = false
        addSubview(statusLabel)
        matchStatusLabel.font = UIFont(name: "IBMPlexMono-Regular", size: 11) ?? .systemFont(ofSize: 11)
        matchStatusLabel.textAlignment = .center
        matchStatusLabel.numberOfLines = 2
        matchStatusLabel.isUserInteractionEnabled = false
        matchStatusLabel.isHidden = true
        addSubview(matchStatusLabel)
        localCallout.isUserInteractionEnabled = false
        addSubview(localCallout)
        updateSearchButton()
        applyAppearance()
    }

    private func install(_ catalog: EmojiCatalog) {
        self.catalog = catalog
        recents.reload(allowSharedAccess: actions.hasFullAccess())
        selectedGroup = recents.sequences.contains(where: { catalog.indexByText[$0] != nil }) ? -1 : 0
        let names = ["Recents"] + catalog.groups.map(\.name)
        let symbols = ["clock"] + catalog.groups.map(\.symbol)
        for index in names.indices {
            let button = UIButton(type: .system)
            button.tag = index - 1
            button.setImage(UIImage(systemName: symbols[index]), for: .normal)
            button.accessibilityLabel = names[index]
            button.layer.cornerRadius = 7
            button.addTarget(self, action: #selector(selectCategory(_:)), for: .touchUpInside)
            categoryScroll.addSubview(button)
            categoryButtons.append(button)
        }
        searchButton.isEnabled = true
        updateBrowseItems()
        applyAppearance()
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let dims = KeyboardDimensions(screenWidth: bounds.width)
        let toolbarHeight = dims.toolbarHeight
        let footerHeight: CGFloat = 46
        if isSearching {
            let queryWidth = min(108, bounds.width * 0.29)
            searchButton.frame = CGRect(x: 4, y: 3, width: queryWidth, height: toolbarHeight - 6)
            cancelButton.frame = CGRect(x: bounds.width - 58, y: 0, width: 58, height: toolbarHeight)
            let matchFrame = CGRect(x: queryWidth + 8, y: 0, width: max(0, bounds.width - queryWidth - 66), height: toolbarHeight)
            if matches.frame != matchFrame {
                matches.frame = matchFrame
                matches.collectionViewLayout.invalidateLayout()
            }
            matchStatusLabel.frame = matchFrame
            searchKeyboard?.frame = CGRect(x: 0, y: toolbarHeight, width: bounds.width, height: max(0, bounds.height - toolbarHeight))
        } else {
            searchButton.frame = CGRect(x: 6, y: 4, width: max(0, bounds.width - 12), height: toolbarHeight - 8)
            let gridFrame = CGRect(x: 0, y: toolbarHeight, width: bounds.width, height: max(0, bounds.height - toolbarHeight - footerHeight))
            if grid.frame != gridFrame {
                grid.frame = gridFrame
                grid.collectionViewLayout.invalidateLayout()
            }
            statusLabel.frame = gridFrame.insetBy(dx: 20, dy: 0)
            abcButton.frame = CGRect(x: 4, y: bounds.height - footerHeight + 2, width: 48, height: 42)
            deleteButton.frame = CGRect(x: bounds.width - 48, y: bounds.height - footerHeight + 2, width: 44, height: 42)
            categoryScroll.frame = CGRect(x: 56, y: bounds.height - footerHeight, width: max(0, bounds.width - 108), height: footerHeight)
            for (index, button) in categoryButtons.enumerated() {
                button.frame = CGRect(x: CGFloat(index) * 44, y: 1, width: 44, height: 44)
            }
            categoryScroll.contentSize = CGSize(width: CGFloat(categoryButtons.count) * 44, height: footerHeight)
        }
        localCallout.frame = bounds
        variantPicker?.frame = bounds
    }

    private func applyAppearance() {
        let foreground: UIColor = isDark ? .white : .black
        let keyColor = isDark ? UIColor(white: 0.4, alpha: 0.55) : UIColor(red: 0.674, green: 0.704, blue: 0.747, alpha: 0.88)
        for button in [searchButton, abcButton, deleteButton, cancelButton] { button.tintColor = foreground }
        for button in [searchButton, abcButton, deleteButton] { button.backgroundColor = keyColor }
        statusLabel.textColor = foreground.withAlphaComponent(0.7)
        matchStatusLabel.textColor = foreground.withAlphaComponent(0.7)
        for button in categoryButtons {
            let selected = button.tag == selectedGroup
            button.tintColor = foreground.withAlphaComponent(selected ? 1 : 0.65)
            button.backgroundColor = selected ? keyColor : .clear
            button.accessibilityTraits = selected ? [.button, .selected] : .button
        }
    }

    @objc private func selectCategory(_ sender: UIButton) {
        dismissVariants()
        selectedGroup = sender.tag
        updateBrowseItems()
        grid.setContentOffset(.zero, animated: false)
        applyAppearance()
    }

    private func updateBrowseItems() {
        guard let catalog else { return }
        browseIndices = selectedGroup == -1
            ? recents.sequences.compactMap { catalog.indexByText[$0] }
            : catalog.groups[selectedGroup].entries
        statusLabel.text = "Recently used emoji appear here"
        statusLabel.isHidden = !browseIndices.isEmpty || isSearching
        grid.reloadData()
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

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        collectionView === grid ? browseIndices.count : matchIndices.count
    }

    private func entryIndex(in collection: UICollectionView, at indexPath: IndexPath) -> Int {
        collection === grid ? browseIndices[indexPath.item] : matchIndices[indexPath.item]
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: EmojiCollectionCell.reuseIdentifier, for: indexPath) as! EmojiCollectionCell
        guard let catalog else { return cell }
        let index = entryIndex(in: collectionView, at: indexPath)
        let entry = catalog.entries[index]
        let hasVariants = !catalog.entries[entry.base].variants.isEmpty
        let chooseVariant: (() -> Void)? = hasVariants ? { [weak self] in self?.showVariants(for: index) } : nil
        cell.configure(entry: entry, hasVariants: hasVariants, isDark: isDark, chooseVariant: chooseVariant)
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout,
                        sizeForItemAt indexPath: IndexPath) -> CGSize {
        if collectionView === matches { return CGSize(width: 44, height: 44) }
        let width = max(0, collectionView.bounds.width - 8)
        let columns = max(1, Int(width / 44))
        return CGSize(width: floor(width / CGFloat(columns)), height: 48)
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
        UIAccessibility.post(notification: .layoutChanged, argument: searchButton)
    }

    @objc private func endSearch() {
        guard isSearching else { return }
        cancelInteraction()
        isSearching = false
        query.clear()
        lastSearchedText = nil
        localState.surface = .typing
        localState.inputTracking.contextMirror.reset(to: nil)
        updateBrowseItems()
        updateSearchVisibility()
        UIAccessibility.post(notification: .layoutChanged, argument: searchButton)
    }

    private func updateSearchVisibility() {
        grid.isHidden = isSearching
        categoryScroll.isHidden = isSearching
        abcButton.isHidden = isSearching
        deleteButton.isHidden = isSearching
        matches.isHidden = !isSearching
        cancelButton.isHidden = !isSearching
        searchKeyboard?.isHidden = !isSearching
        statusLabel.isHidden = isSearching || !browseIndices.isEmpty
        matchStatusLabel.isHidden = !isSearching || !matchIndices.isEmpty
        updateSearchButton()
        setNeedsLayout()
    }

    private func updateSearchButton() {
        searchButton.setTitle(isSearching ? " " + (query.text.isEmpty ? "Search" : query.text) : " Search emoji", for: .normal)
        searchButton.accessibilityValue = isSearching ? (query.text.isEmpty ? "Empty query" : query.text) : nil
        searchButton.accessibilityHint = isSearching ? "Type using the keys below. Text stays in emoji search." : "Opens local emoji search."
        searchButton.accessibilityCustomActions = isSearching ? [UIAccessibilityCustomAction(name: "Clear search") { [weak self] _ in
            guard let self else { return false }
            self.query.clear()
            self.queryDidChange()
            return true
        }] : nil
    }

    private func refreshSearch() {
        guard let catalog, isSearching, lastSearchedText != query.text else { return }
        lastSearchedText = query.text
        matchIndices = query.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? (recents.sequences.isEmpty ? Array(catalog.groups[0].entries.prefix(40)) : recents.sequences.compactMap { catalog.indexByText[$0] })
            : catalog.search(query.text)
        updateSearchButton()
        matches.reloadData()
        matches.setContentOffset(.zero, animated: false)
        matchStatusLabel.text = "No matches"
        matchStatusLabel.isHidden = !matchIndices.isEmpty
    }

    private func queryDidChange() {
        localState.inputTracking.contextMirror.reset(to: query.contextBeforeInput)
        refreshSearch()
    }

    private func moveQueryCaret(by offset: Int) {
        query.moveCaret(by: offset)
        localState.inputTracking.contextMirror.reset(to: query.contextBeforeInput)
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
            openApp: {}, hasFullAccess: { false }, requestReminder: {},
            createReminder: { _, _ in }, createTimer: { _, _ in }, pasteFromClipboard: {},
            copySnippetFile: { _ in .noFullAccess }, evaluateSlashCommand: {}, evaluatePredictiveText: {},
            scheduleSideEffects: { [weak self] in
                // Search spaces are literal; double-space must not become a period.
                self?.localState.inputTracking.resetAutoPeriodTracking()
                self?.refreshSearch()
            },
            adjustCaret: { [weak self] in self?.moveQueryCaret(by: $0) },
            inputTraits: { traits }, activeInputLocaleCodes: { [] },
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
