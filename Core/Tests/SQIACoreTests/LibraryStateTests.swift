// The library's rows and the grid they sit in.

import Foundation
import Testing

@testable import SQIACore

private func project(_ id: String, _ name: String) -> Project {
    Project(
        id: id, name: name, bpm: 120, rootPc: 9, scale: "minor",
        tracks: [], updatedAt: "2026-08-21T12:00:00Z")
}

@Suite("Library rows")
struct LibraryStateTests {
    @Test("A new project goes to the front without waiting for a reload")
    func insertGoesFirst() {
        var state = LibraryState(rows: [project("a", "A"), project("b", "B")])
        state.insert(project("c", "C"))
        #expect(state.rows.map(\.name) == ["C", "A", "B"])
    }

    @Test("Reopening a project the library already knows does not double it")
    func insertIsIdempotent() {
        var state = LibraryState(rows: [project("a", "A"), project("b", "B")])
        state.insert(project("b", "B renamed"))
        #expect(state.rows.map(\.id) == ["b", "a"])
        #expect(state.rows[0].name == "B renamed")
    }

    @Test("Renaming keeps the card where the eye left it")
    func renameDoesNotReorder() {
        var state = LibraryState(rows: [project("a", "A"), project("b", "B")])
        let previous = state.rename(id: "b", to: "Bee")
        #expect(previous == "B")
        #expect(state.rows.map(\.name) == ["A", "Bee"])
        // A row that is not there says so rather than pretending.
        #expect(state.rename(id: "zz", to: "Nope") == nil)
    }

    @Test("A failed delete puts the card back where it was")
    func removeAndRestore() {
        var state = LibraryState(
            rows: [project("a", "A"), project("b", "B"), project("c", "C")])
        let gone = state.remove(id: "b")
        #expect(gone?.at == 1)
        #expect(state.rows.map(\.name) == ["A", "C"])

        state.restore(gone!.project, at: gone!.at)
        #expect(state.rows.map(\.name) == ["A", "B", "C"])
        #expect(state.remove(id: "zz") == nil)
    }

    @Test("Restoring a row whose neighbours have gone still lands somewhere")
    func restoreClamps() {
        var state = LibraryState(rows: [project("a", "A")])
        state.restore(project("z", "Z"), at: 9)
        #expect(state.rows.map(\.name) == ["A", "Z"])
    }
}

@Suite("Library list")
struct LibraryLayoutTests {
    @Test("On a phone a card fills the width between the margins")
    func phoneStretches() {
        #expect(LibraryLayout.cardWidth(screen: 375) == 335)
        #expect(LibraryLayout.cardWidth(screen: 430) == 390)
    }

    @Test("Past 460 a card stops growing")
    func wideStopsAt460() {
        #expect(LibraryLayout.cardWidth(screen: 500) == 460)
        #expect(LibraryLayout.cardWidth(screen: 1024) == 460)
    }

    @Test("A screen too narrow to hold anything asks for nothing negative")
    func absurdlyNarrow() {
        #expect(LibraryLayout.cardWidth(screen: 30) == 0)
    }
}
