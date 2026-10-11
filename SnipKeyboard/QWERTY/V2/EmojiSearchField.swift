import UIKit
import CoreText

/// Draws and edits only EmojiSearchQuery. It never becomes first responder or opens
/// another keyboard, so neither tapping nor dragging can move the host caret.
@MainActor
final class EmojiSearchField: UIView, UIGestureRecognizerDelegate {
    var onBeginEditing: (() -> Void)?
    var onSetCaret: ((Int) -> Void)?
    var onClear: (() -> Void)?
    var isEnabled = false { didSet { isUserInteractionEnabled = isEnabled } }

    private let icon = UIImageView(image: UIImage(systemName: "magnifyingglass"))
    private let viewport = UIView()
    private let textLabel = UILabel()
    private let caretView = UIView()
    private let clearButton = UIButton(type: .system)
    private var text = ""
    private var caret = 0
    private var isEditing = false
    private var caretPositions: [CGFloat] = [0]
    private var textWidth: CGFloat = 0
    private var textOffset: CGFloat = 0
    private let font = UIFont.systemFont(ofSize: 17)

    override init(frame: CGRect) {
        super.init(frame: frame)
        isAccessibilityElement = true
        accessibilityLabel = "Search emoji"
        accessibilityTraits = .searchField
        icon.contentMode = .scaleAspectFit
        icon.tintColor = .secondaryLabel
        addSubview(icon)
        viewport.clipsToBounds = true
        viewport.isUserInteractionEnabled = false
        addSubview(viewport)
        textLabel.font = font
        textLabel.textAlignment = .left
        textLabel.semanticContentAttribute = .forceLeftToRight
        viewport.addSubview(textLabel)
        caretView.backgroundColor = .systemBlue
        caretView.layer.cornerRadius = 1
        viewport.addSubview(caretView)
        clearButton.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
        clearButton.tintColor = .secondaryLabel
        clearButton.accessibilityLabel = "Clear search"
        clearButton.addTarget(self, action: #selector(clear), for: .touchUpInside)
        addSubview(clearButton)
        let tap = UITapGestureRecognizer(target: self, action: #selector(tapped(_:)))
        tap.delegate = self
        addGestureRecognizer(tap)
        let drag = UIPanGestureRecognizer(target: self, action: #selector(dragged(_:)))
        drag.maximumNumberOfTouches = 1
        drag.delegate = self
        addGestureRecognizer(drag)
        update(text: "", caret: 0, isEditing: false)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    func update(text: String, caret: Int, isEditing: Bool) {
        let changedText = self.text != text || textLabel.text == nil
        let changedMode = self.isEditing != isEditing
        guard changedText || changedMode || self.caret != caret else { return }
        if changedText {
            self.text = text
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [.font: font]))
            textWidth = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
            caretPositions.removeAll(keepingCapacity: true)
            caretPositions.reserveCapacity(text.count + 1)
            caretPositions.append(0)
            var index = text.startIndex
            while index < text.endIndex {
                index = text.index(after: index)
                caretPositions.append(CTLineGetOffsetForStringIndex(line, index.utf16Offset(in: text), nil))
            }
        }
        self.caret = min(max(0, caret), caretPositions.count - 1)
        self.isEditing = isEditing
        if changedText {
            textLabel.text = text.isEmpty ? "Search Emoji" : text
            textLabel.textColor = text.isEmpty ? .secondaryLabel : .label
        }
        caretView.isHidden = !isEditing
        clearButton.isHidden = !isEditing || text.isEmpty
        accessibilityValue = text.isEmpty ? "Empty query" : text
        accessibilityHint = isEditing ? "Type with the keys below. Swipe up or down to move the search caret." : "Opens local emoji search."
        accessibilityTraits = isEditing ? [.searchField, .adjustable] : [.searchField, .button]
        if changedMode {
            accessibilityCustomActions = isEditing ? [UIAccessibilityCustomAction(name: "Clear search") { [weak self] _ in
                self?.onClear?()
                return true
            }] : nil
            updateCaretAnimation()
        }
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = bounds.height / 2
        icon.frame = CGRect(x: 12, y: (bounds.height - 20) / 2, width: 20, height: 20)
        clearButton.frame = CGRect(x: bounds.width - 40, y: 0, width: 40, height: bounds.height)
        viewport.frame = CGRect(x: 40, y: 0, width: max(0, bounds.width - 40 - (clearButton.isHidden ? 12 : 40)), height: bounds.height)
        let caretX = caretPositions[caret]
        let visibleWidth = max(0, viewport.bounds.width - 2)
        if caretX - textOffset > visibleWidth { textOffset = caretX - visibleWidth }
        if caretX < textOffset { textOffset = caretX }
        textOffset = max(0, min(textOffset, max(0, textWidth - visibleWidth)))
        textLabel.frame = CGRect(x: -textOffset, y: 0, width: max(viewport.bounds.width, textWidth + 2), height: bounds.height)
        caretView.frame = CGRect(x: caretX - textOffset, y: (bounds.height - 23) / 2, width: 2, height: 23)
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        !(!clearButton.isHidden && clearButton.frame.contains(touch.location(in: self)))
    }

    @objc private func tapped(_ recognizer: UITapGestureRecognizer) {
        onBeginEditing?()
        positionCaret(at: recognizer.location(in: viewport).x)
    }

    @objc private func dragged(_ recognizer: UIPanGestureRecognizer) {
        guard recognizer.state == .began || recognizer.state == .changed else { return }
        if recognizer.state == .began { onBeginEditing?() }
        positionCaret(at: recognizer.location(in: viewport).x)
    }

    private func positionCaret(at x: CGFloat) {
        let target = x + textOffset
        guard let index = caretPositions.indices.min(by: { abs(caretPositions[$0] - target) < abs(caretPositions[$1] - target) }) else { return }
        if index != caret { onSetCaret?(index) }
        layoutIfNeeded()
    }

    @objc private func clear() { onClear?() }

    override func accessibilityActivate() -> Bool {
        onBeginEditing?()
        return true
    }

    override func accessibilityIncrement() { onSetCaret?(min(caret + 1, caretPositions.count - 1)) }
    override func accessibilityDecrement() { onSetCaret?(max(0, caret - 1)) }

    private func updateCaretAnimation() {
        caretView.layer.removeAnimation(forKey: "caretBlink")
        guard isEditing, window != nil, !UIAccessibility.isReduceMotionEnabled else { return }
        let blink = CABasicAnimation(keyPath: "opacity")
        blink.fromValue = 1
        blink.toValue = 0
        blink.duration = 0.55
        blink.autoreverses = true
        blink.repeatCount = .infinity
        caretView.layer.add(blink, forKey: "caretBlink")
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        updateCaretAnimation()
    }
}
