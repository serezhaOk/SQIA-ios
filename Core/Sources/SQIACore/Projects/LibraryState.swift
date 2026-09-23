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

/// The list, from the 375pt mockup.
///
/// One column of tall cards, 20 in from either edge, until a card would be
/// wider than 460 — past that it stops growing and the column is centred,
/// so an iPad gets the same card a big phone does rather than a banner.
public enum LibraryLayout {
    public static let margin = 20.0
    public static let gap = 12.0
    public static let cardHeight = 306.0
    public static let maxCardWidth = 460.0
    public static let cornerRadius = 32.0
    public static let headHeight = 48.0
    /// Below the safe area. The mockup's 56 is this over a 44pt status bar.
    public static let headTop = 12.0
    public static let listTop = 24.0
    /// The empty card runs to this far off the bottom edge of the screen.
    public static let emptyBottom = 20.0
    public static let createWidth = 175.0
    public static let createHeight = 50.0
    /// From the bottom edge of the screen, not of the safe area.
    public static let createBottom = 40.0
    /// The blur the list goes under, measured up from the screen's edge.
    public static let blurHeight = 110.0

    /// How wide a card is on a screen this wide.
    public static func cardWidth(screen width: Double) -> Double {
        max(0, min(width - 2 * margin, maxCardWidth))
    }
}
