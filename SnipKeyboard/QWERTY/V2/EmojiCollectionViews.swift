import UIKit

@MainActor
final class EmojiBrowseLayout: UICollectionViewLayout {
    var itemCounts: [Int] = [] {
        didSet { if oldValue != itemCounts { invalidateLayout() } }
    }
    private(set) var geometry = EmojiBrowseGeometry(viewport: .zero, itemCounts: [])

    override func prepare() {
        super.prepare()
        guard let collectionView else { return }
        if geometry.viewport != collectionView.bounds.size || geometry.itemCounts != itemCounts {
            geometry = EmojiBrowseGeometry(viewport: collectionView.bounds.size, itemCounts: itemCounts)
        }
    }

    override var collectionViewContentSize: CGSize { geometry.contentSize }

    override func shouldInvalidateLayout(forBoundsChange newBounds: CGRect) -> Bool {
        newBounds.size != geometry.viewport
    }

    override func layoutAttributesForItem(at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
        guard geometry.itemCounts.indices.contains(indexPath.section),
              (0..<geometry.itemCounts[indexPath.section]).contains(indexPath.item) else { return nil }
        let attributes = UICollectionViewLayoutAttributes(forCellWith: indexPath)
        attributes.frame = geometry.frame(section: indexPath.section, item: indexPath.item)
        return attributes
    }

    override func layoutAttributesForElements(in rect: CGRect) -> [UICollectionViewLayoutAttributes]? {
        guard geometry.cellSize.width > 0 else { return [] }
        var attributes: [UICollectionViewLayoutAttributes] = []
        for section in geometry.itemCounts.indices {
            let start = geometry.sectionOffsets[section] + 4
            let end = geometry.sectionOffsets[section] + geometry.sectionWidths[section]
            guard rect.maxX >= start, rect.minX <= end else { continue }
            let firstColumn = max(0, Int(floor((rect.minX - start) / geometry.cellSize.width)))
            let lastColumn = max(firstColumn, Int(floor((rect.maxX - start) / geometry.cellSize.width)))
            let first = min(geometry.itemCounts[section], firstColumn * EmojiBrowseGeometry.rows)
            let endItem = min(geometry.itemCounts[section], (lastColumn + 1) * EmojiBrowseGeometry.rows)
            for item in first..<endItem {
                if let value = layoutAttributesForItem(at: IndexPath(item: item, section: section)) {
                    attributes.append(value)
                }
            }
        }
        return attributes
    }
}

@MainActor
final class EmojiCategoryButton: UIButton {
    private let selectionBackground = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        selectionBackground.isUserInteractionEnabled = false
        selectionBackground.isHidden = true
        insertSubview(selectionBackground, at: 0)
        setPreferredSymbolConfiguration(UIImage.SymbolConfiguration(pointSize: 20, weight: .regular), forImageIn: .normal)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    override var isSelected: Bool {
        didSet { selectionBackground.isHidden = !isSelected }
    }

    override var isHighlighted: Bool {
        didSet { alpha = isHighlighted ? 0.5 : 1 }
    }

    func setSelectionColor(_ color: UIColor) { selectionBackground.backgroundColor = color }

    override func layoutSubviews() {
        super.layoutSubviews()
        let side = max(0, min(32, bounds.width - 2, bounds.height - 4))
        selectionBackground.frame = CGRect(x: (bounds.width - side) / 2, y: (bounds.height - side) / 2, width: side, height: side)
        selectionBackground.layer.cornerRadius = side / 2
        sendSubviewToBack(selectionBackground)
    }
}

@MainActor
final class EmojiCollectionCell: UICollectionViewCell {
    static let reuseIdentifier = "EmojiCollectionCell"
    private let glyph = UILabel()
    private let variantMark = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isAccessibilityElement = true
        accessibilityTraits = .button
        glyph.textAlignment = .center
        glyph.font = .systemFont(ofSize: 32)
        glyph.isAccessibilityElement = false
        contentView.addSubview(glyph)
        variantMark.layer.cornerRadius = 2
        variantMark.isUserInteractionEnabled = false
        contentView.addSubview(variantMark)
        contentView.layer.cornerRadius = 7
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    override func layoutSubviews() {
        super.layoutSubviews()
        glyph.frame = contentView.bounds.insetBy(dx: 2, dy: 1)
        let fontSize = min(34, max(18, min(bounds.width, bounds.height) - 8))
        if glyph.font.pointSize != fontSize { glyph.font = .systemFont(ofSize: fontSize) }
        variantMark.frame = CGRect(x: contentView.bounds.maxX - 7, y: contentView.bounds.maxY - 6, width: 3, height: 3)
    }

    func configure(entry: EmojiCatalog.Entry, hasVariants: Bool, isDark: Bool,
                   chooseVariant: (() -> Void)? = nil) {
        glyph.text = entry.text
        setNeedsLayout()
        accessibilityLabel = entry.name
        accessibilityHint = hasVariants ? "Double-tap to insert. Skin tones available in Actions." : "Double-tap to insert."
        variantMark.isHidden = !hasVariants
        variantMark.backgroundColor = isDark ? .lightGray : .darkGray
        accessibilityCustomActions = chooseVariant.map { action in
            [UIAccessibilityCustomAction(name: "Choose skin tone") { _ in
                action()
                return true
            }]
        }
    }

    override var isHighlighted: Bool {
        didSet { contentView.backgroundColor = isHighlighted ? UIColor.label.withAlphaComponent(0.12) : .clear }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        accessibilityCustomActions = nil
        contentView.backgroundColor = .clear
    }
}

/// In-keyboard picker rather than a presentation controller: custom input views cannot
/// reliably present popovers. Mixed-tone couples can have 25 variants, so this scrolls.
@MainActor
final class EmojiVariantPicker: UIView, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    private let catalog: EmojiCatalog
    private let indices: [Int]
    private let isDark: Bool
    private let onSelect: (Int) -> Void
    private let onDismiss: () -> Void
    private let card = UIView()
    private let titleLabel = UILabel()
    private let closeButton = UIButton(type: .system)
    private let collection: UICollectionView
    private let outsideButton = UIButton(type: .custom)

    init(catalog: EmojiCatalog, base: Int, isDark: Bool,
         onSelect: @escaping (Int) -> Void, onDismiss: @escaping () -> Void) {
        self.catalog = catalog
        indices = [base] + catalog.entries[base].variants
        self.isDark = isDark
        self.onSelect = onSelect
        self.onDismiss = onDismiss
        let layout = UICollectionViewFlowLayout()
        layout.minimumInteritemSpacing = 0
        layout.minimumLineSpacing = 0
        collection = UICollectionView(frame: .zero, collectionViewLayout: layout)
        super.init(frame: .zero)
        accessibilityViewIsModal = true
        outsideButton.addTarget(self, action: #selector(dismiss), for: .touchUpInside)
        outsideButton.accessibilityLabel = "Dismiss skin tones"
        addSubview(outsideButton)
        card.backgroundColor = isDark ? UIColor(white: 0.18, alpha: 1) : .white
        card.layer.cornerRadius = 12
        card.layer.shadowColor = UIColor.black.cgColor
        card.layer.shadowOpacity = 0.25
        card.layer.shadowRadius = 8
        addSubview(card)
        titleLabel.text = "Skin tones"
        titleLabel.font = .systemFont(ofSize: 14, weight: .medium)
        titleLabel.textColor = isDark ? .white : .black
        titleLabel.accessibilityTraits = .header
        card.addSubview(titleLabel)
        closeButton.setImage(UIImage(systemName: "xmark"), for: .normal)
        closeButton.tintColor = isDark ? .white : .black
        closeButton.accessibilityLabel = "Close skin tones"
        closeButton.addTarget(self, action: #selector(dismiss), for: .touchUpInside)
        card.addSubview(closeButton)
        collection.backgroundColor = .clear
        collection.dataSource = self
        collection.delegate = self
        collection.register(EmojiCollectionCell.self, forCellWithReuseIdentifier: EmojiCollectionCell.reuseIdentifier)
        card.addSubview(collection)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    override func layoutSubviews() {
        super.layoutSubviews()
        outsideButton.frame = bounds
        outsideButton.backgroundColor = UIColor.black.withAlphaComponent(0.12)
        let width = min(max(0, bounds.width - 16), 360)
        let columns = max(1, Int(width / 48))
        let rows = (indices.count + columns - 1) / columns
        let height = min(max(0, bounds.height - 12), CGFloat(rows) * 48 + 44)
        card.frame = CGRect(x: (bounds.width - width) / 2, y: (bounds.height - height) / 2, width: width, height: height)
        titleLabel.frame = CGRect(x: 14, y: 0, width: max(0, width - 58), height: 44)
        closeButton.frame = CGRect(x: width - 44, y: 0, width: 44, height: 44)
        let collectionFrame = CGRect(x: 0, y: 44, width: width, height: max(0, height - 44))
        if collection.frame != collectionFrame {
            collection.frame = collectionFrame
            collection.collectionViewLayout.invalidateLayout()
        }
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int { indices.count }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: EmojiCollectionCell.reuseIdentifier, for: indexPath) as! EmojiCollectionCell
        cell.configure(entry: catalog.entries[indices[indexPath.item]], hasVariants: false, isDark: isDark)
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout,
                        sizeForItemAt indexPath: IndexPath) -> CGSize {
        let columns = max(1, Int(collectionView.bounds.width / 48))
        return CGSize(width: floor(collectionView.bounds.width / CGFloat(columns)), height: 48)
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        onSelect(indices[indexPath.item])
    }

    override func accessibilityPerformEscape() -> Bool {
        onDismiss()
        return true
    }

    @objc private func dismiss() { onDismiss() }
}

@MainActor
final class EmojiDeleteButton: UIButton {
    override func accessibilityActivate() -> Bool {
        sendActions(for: .touchDown)
        sendActions(for: .touchUpInside)
        return true
    }
}
