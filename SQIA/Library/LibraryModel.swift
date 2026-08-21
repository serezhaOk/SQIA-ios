// The library screen's state.
//
// Everything the screen can do is a round trip that might fail, and none of
// it waits: the card is renamed on screen before the store has agreed, and
// put back if it refuses. `LibraryState` in Core holds the rows and the
// undo; this holds the store and the failure text.

import Foundation
import SQIACore

@MainActor
@Observable
final class LibraryModel {
    private(set) var state = LibraryState()
    /// True only for the first load. A reload behind an already-drawn
    /// library does not blank it out.
    private(set) var isLoading = true
    private(set) var failure: String?

    @ObservationIgnored let store: any ProjectStore

    init(store: any ProjectStore) {
        self.store = store
    }

    var rows: [Project] { state.rows }
    var isEmpty: Bool { state.isEmpty }

    func load() async {
        do {
            state.replace(with: try await store.list())
            failure = nil
        } catch {
            // On the first load there is nothing to keep, and an empty
            // library is what the web shows when the list fails. On a
            // reload there are rows on screen already, and throwing them
            // away because one request failed would be worse than stale.
            if isLoading { state.replace(with: []) }
            failure = Self.text(error)
        }
        isLoading = false
    }

    /// A fresh project, saved before it is opened so the first edit has a
    /// row to write to.
    func create(_ snapshot: ProjectSnapshot) async -> Project? {
        do {
            let project = try await store.create(name: nil, snapshot: snapshot)
            state.insert(project)
            failure = nil
            return project
        } catch {
            failure = Self.text(error)
            return nil
        }
    }

    func rename(id: String, to name: String) async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let previous = state.rename(id: id, to: trimmed),
            previous != trimmed
        else { return }
        do {
            try await store.rename(id: id, to: trimmed)
            failure = nil
        } catch {
            state.rename(id: id, to: previous)
            failure = Self.text(error)
        }
    }

    func delete(id: String) async {
        guard let gone = state.remove(id: id) else { return }
        do {
            try await store.delete(id: id)
            failure = nil
        } catch {
            state.restore(gone.project, at: gone.at)
            failure = Self.text(error)
        }
    }

    private static func text(_ error: Error) -> String {
        switch error as? ProjectStoreError {
        case .notSignedIn: return "Sign in to keep projects"
        case .notFound: return "That project is gone"
        case .transport(let message): return message
        case nil: return error.localizedDescription
        }
    }
}
