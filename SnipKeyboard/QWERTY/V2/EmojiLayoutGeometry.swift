import Foundation
import CoreGraphics

/// Column-major geometry shared by the collection layout and its host-only smoke harness.
struct EmojiBrowseGeometry {
    static let rows = 4
    let viewport: CGSize
    let itemCounts: [Int]
    let cellSize: CGSize
    let sectionOffsets: [CGFloat]
    let sectionWidths: [CGFloat]
    let contentSize: CGSize

    init(viewport: CGSize, itemCounts: [Int]) {
        self.viewport = viewport
        self.itemCounts = itemCounts
        let usableWidth = max(0, viewport.width - 8)
        // Portrait phones retain the reference's eight-column density rather than
        // squeezing in a ninth column as the screen gets wider.
        let fittingColumns = max(1, Int(usableWidth / 46))
        let columns = viewport.width < 600 ? min(8, fittingColumns) : fittingColumns
        cellSize = CGSize(width: usableWidth / CGFloat(columns), height: max(0, viewport.height - 4) / CGFloat(Self.rows))
        var offsets: [CGFloat] = []
        var widths: [CGFloat] = []
        offsets.reserveCapacity(itemCounts.count)
        widths.reserveCapacity(itemCounts.count)
        var offset: CGFloat = 0
        for count in itemCounts {
            let columnCount = (max(0, count) + Self.rows - 1) / Self.rows
            let width = max(viewport.width, CGFloat(columnCount) * cellSize.width + 8)
            offsets.append(offset)
            widths.append(width)
            offset += width
        }
        sectionOffsets = offsets
        sectionWidths = widths
        contentSize = CGSize(width: offset, height: viewport.height)
    }

    func frame(section: Int, item: Int) -> CGRect {
        CGRect(x: sectionOffsets[section] + 4 + CGFloat(item / Self.rows) * cellSize.width,
               y: 2 + CGFloat(item % Self.rows) * cellSize.height,
               width: cellSize.width, height: cellSize.height)
    }

    func offset(forSection section: Int) -> CGFloat {
        min(max(0, sectionOffsets[section]), max(0, contentSize.width - viewport.width))
    }

    func section(atOffset offset: CGFloat) -> Int? {
        guard !sectionOffsets.isEmpty else { return nil }
        let leadingEdge = max(0, offset) + 4
        return sectionOffsets.lastIndex(where: { $0 <= leadingEdge }) ?? 0
    }
}

struct EmojiSurfaceGeometry {
    static let searchAdditionalHeight: CGFloat = 52
    let search: CGRect
    let results: CGRect
    let keys: CGRect
    let browse: CGRect
    let footer: CGRect
    let abc: CGRect
    let delete: CGRect
    let categories: [CGRect]

    init(size: CGSize, headerHeight: CGFloat, keysHeight: CGFloat, categoryCount: Int) {
        search = CGRect(x: 8, y: 3, width: max(0, size.width - 16), height: max(0, headerHeight - 6))
        results = CGRect(x: 0, y: headerHeight, width: size.width, height: Self.searchAdditionalHeight)
        keys = CGRect(x: 0, y: results.maxY, width: size.width, height: keysHeight)
        let footerHeight: CGFloat = 44
        footer = CGRect(x: 0, y: max(headerHeight, size.height - footerHeight), width: size.width, height: footerHeight)
        browse = CGRect(x: 0, y: headerHeight, width: size.width, height: max(0, footer.minY - headerHeight))
        abc = CGRect(x: 2, y: footer.minY, width: 46, height: footerHeight)
        delete = CGRect(x: max(48, size.width - 44), y: footer.minY, width: 42, height: footerHeight)
        let categoryWidth = max(0, delete.minX - abc.maxX) / CGFloat(max(1, categoryCount))
        let categoriesX = abc.maxX
        let categoriesY = footer.minY
        categories = (0..<categoryCount).map {
            CGRect(x: categoriesX + CGFloat($0) * categoryWidth, y: categoriesY, width: categoryWidth, height: footerHeight)
        }
    }
}
