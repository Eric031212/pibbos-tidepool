import Foundation

/// Where the seed picker draws its packets (v2.3): a panel with a title line,
/// a grid of up to six packets per row and two rows, and ◀ ▶ arrows to turn
/// the page once there are more seeds than fit. Pure layout, so new flowers
/// only need art and a name.
public enum SeedPicker {
    public static let columns = 6
    public static let rows = 2
    public static let perPage = columns * rows
    public static let cell = 14
    public static let seedSize = 12
    /// Height of the title line at the top of the panel.
    public static let titleBand = 13
    public static let arrowSize = (w: 5, h: 7)

    public struct Slot: Equatable, Sendable {
        /// Index into the list of kinds.
        public let index: Int
        public let x: Int
        public let y: Int
    }

    public struct Layout: Equatable, Sendable {
        public let x: Int, y: Int, w: Int, h: Int
        /// "panel1" or "panel2": the sheet's panel for one or two rows.
        public let panel: String
        public let slots: [Slot]
        public let pages: Int
        /// Where the arrows go, when there's a page that way.
        public let previous: (x: Int, y: Int)?
        public let next: (x: Int, y: Int)?

        public static func == (a: Layout, b: Layout) -> Bool {
            a.x == b.x && a.y == b.y && a.w == b.w && a.h == b.h && a.panel == b.panel && a.slots == b.slots && a.pages == b.pages
                && a.previous?.x == b.previous?.x && a.next?.x == b.next?.x
        }

        /// The panel's title: centred, at the top.
        public var titleX: Int { x + w / 2 }
        public var titleY: Int { y + 3 }

        public func contains(_ p: GamePoint) -> Bool {
            p.x >= Double(x) && p.x < Double(x + w) && p.y >= Double(y) && p.y < Double(y + h)
        }

        public func slot(at p: GamePoint) -> Slot? {
            slots.first { s in
                p.x >= Double(s.x) && p.x < Double(s.x + SeedPicker.seedSize) && p.y >= Double(s.y) && p.y < Double(s.y + SeedPicker.seedSize)
            }
        }

        static func hit(_ arrow: (x: Int, y: Int)?, _ p: GamePoint) -> Bool {
            guard let a = arrow else { return false }  // a little slack: the arrows are small
            return p.x >= Double(a.x - 2) && p.x < Double(a.x + SeedPicker.arrowSize.w + 2)
                && p.y >= Double(a.y - 2) && p.y < Double(a.y + SeedPicker.arrowSize.h + 2)
        }
        public func isPrevious(_ p: GamePoint) -> Bool { Self.hit(previous, p) }
        public func isNext(_ p: GamePoint) -> Bool { Self.hit(next, p) }
    }

    public static func pages(count: Int) -> Int { max(1, (count + perPage - 1) / perPage) }

    public static func layout(count: Int, page: Int, top: Int = 12) -> Layout {
        let pages = pages(count: count)
        let page = min(max(page, 0), pages - 1)
        let rowsShown = count > columns ? rows : 1
        let w = columns * cell + 4
        let h = titleBand + rowsShown * cell + 3
        let x = (Playfield.width - w) / 2
        let first = page * perPage
        let onPage = max(0, min(perPage, count - first))
        var slots: [Slot] = []
        for i in 0..<onPage {
            let row = i / columns, col = i % columns
            let inRow = min(columns, onPage - row * columns)
            let indent = (columns - inRow) * cell / 2  // a short last row sits in the middle
            slots.append(Slot(index: first + i, x: x + 3 + indent + col * cell, y: top + titleBand + row * cell))
        }
        return Layout(x: x, y: top, w: w, h: h, panel: rowsShown == 1 ? "panel1" : "panel2", slots: slots, pages: pages,
                      previous: page > 0 ? (x + 3, top + 3) : nil,
                      next: page < pages - 1 ? (x + w - 3 - arrowSize.w, top + 3) : nil)
    }
}
