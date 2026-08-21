// The library's rows as the screen holds them, and the grid they sit in.
//
// The screen edits its rows before the store has agreed to anything: a
// rename shows the new name at once, a delete takes the card away at once.
// That is the web's behaviour and it is the right one — waiting on a round
// trip to redraw a label is how an app feels slow. What is here that the
// web does not have is the other half of it: if the write fails, the row
// goes back where it was. The web leaves the lie on screen until the next
// load, which is a thing the user finds out about later and at the worst
// moment.

import Foundation

public struct LibraryState: Sendable, Equatable {
    /// Newest first, which is the order the store lists them in.
    public private(set) var rows: [Project] = []

    public init(rows: [Project] = []) {
        self.rows = rows
    }

    public var isEmpty: Bool { rows.isEmpty }

    public func index(of id: String) -> Int? {
        rows.firstIndex { $0.id == id }
    }

    public mutating func replace(with rows: [Project]) {
        self.rows = rows
    }

    /// A new project goes to the front, where ordering by `updated_at` puts
    /// it without waiting for a reload.
    public mutating func insert(_ project: Project) {
        rows.removeAll { $0.id == project.id }
        rows.insert(project, at: 0)
    }

    /// Renaming does not reorder. The card keeps the place the eye left it
    /// in, even though the row it stands for has just been written.
    @discardableResult
    public mutating func rename(id: String, to name: String) -> String? {
        guard let index = index(of: id) else { return nil }
        let previous = rows[index].name
        rows[index].name = name
        return previous
    }

    /// Returns what was removed, and where, so a failed delete can be undone.
    @discardableResult
    public mutating func remove(id: String) -> (project: Project, at: Int)? {
        guard let index = index(of: id) else { return nil }
        return (rows.remove(at: index), index)
    }

    public mutating func restore(_ project: Project, at index: Int) {
        rows.insert(project, at: min(max(0, index), rows.count))
    }
}

/// The grid, from the 375pt mockup and the one breakpoint above it.
///
/// Below 768 the cards stretch: two columns, whatever is left over after the
/// margins. At 768 and up they stop stretching and become fixed 200pt tiles
/// laid out from the centre, which is what `repeat(auto-fill, 200px)` inside
/// a centred 848pt column comes to.
public enum LibraryLayout {
    public static let breakpoint = 768.0
    public static let margin = 20.0
    public static let gap = 7.0
    public static let tile = 200.0
    public static let maxWidth = 848.0
    public static let cornerRadius = 20.0
    public static let cardPadding = 20.0
    /// The empty state is one tall card, the height of a screenful.
    public static let emptyHeight = 602.0
    public static let emptyHeightWide = 200.0
    public static let createHeight = 50.0
    public static let createInset = 24.0
    public static let createBottom = 40.0
    public static let headHeight = 40.0
    public static let headTop = 35.0
    public static let titleTop = 23.0
    public static let listTop = 16.0
    public static let profile = CGSize(width: 52, height: 39)

    public static func layout(width: Double) -> (columns: Int, side: Double) {
        guard width >= breakpoint else {
            return (2, max(0, (width - 2 * margin - gap) / 2))
        }
        let available = min(width, maxWidth)
        var columns = 1
        while Double(columns + 1) * tile + Double(columns) * gap <= available {
            columns += 1
        }
        return (columns, tile)
    }

    /// The whole grid's width, so a wide screen can centre it.
    public static func gridWidth(_ layout: (columns: Int, side: Double)) -> Double {
        Double(layout.columns) * layout.side + Double(layout.columns - 1) * gap
    }
}
