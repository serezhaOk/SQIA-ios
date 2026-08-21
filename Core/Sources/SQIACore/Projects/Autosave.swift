// Saving without anybody asking, and without saving forty times a bar.
//
// Direct port of `makeAutosave` in the web app's src/projects.ts, whose
// behaviour is more particular than "debounce" covers:
//
//   - only the newest job is kept, so a burst of edits becomes one write;
//   - the wait restarts on every edit, so a continuous drag saves once it
//     stops rather than all the way through;
//   - one request is ever in flight, and an edit that arrives during one
//     waits for it rather than racing it;
//   - a failure is swallowed. There is no error to show somebody who is
//     drawing: the next edit will try again, and the pattern in front of
//     them is the truth either way.
//
// The waiting and the writing are deliberately two tasks. In the browser
// `clearTimeout` cannot reach a request that has already left, but a Swift
// task cancel reaches everything below it — so if the write lived inside
// the timer, the next edit would cancel the request it was waiting on and
// the save would be lost mid-flight. The timer is cancellable; the writer
// is not.

import Foundation

public actor Autosave {
    public typealias Job = @Sendable () async throws -> Void
    /// How the window is waited out. Only a test passes anything else, and
    /// it passes something it can open by hand — otherwise "the timer has
    /// not fired yet" is a claim about a loaded machine's scheduler rather
    /// than about this file.
    public typealias Wait = @Sendable (Duration) async -> Void

    /// The web waits 1.2 seconds.
    public static let defaultDelay = Duration.milliseconds(1200)

    private let delay: Duration
    private let waiting: Wait
    private var pending: Job?
    /// Waits out the debounce. Cancelled by the next edit.
    private var timer: Task<Void, Never>?
    /// Performs the write. Never cancelled by an edit.
    private var writer: Task<Void, Never>?

    /// How many writes actually happened, and how many were swallowed.
    /// Nothing depends on them; they are what a test can look at.
    public private(set) var saves = 0
    public private(set) var failures = 0

    /// True while a write is in the air.
    public var isWriting: Bool { writer != nil }

    public init(
        delay: Duration = Autosave.defaultDelay,
        waiting: @escaping Wait = { try? await Task.sleep(for: $0) }
    ) {
        self.delay = delay
        self.waiting = waiting
    }

    /// Note an edit. Only the last job scheduled inside the window runs.
    public func schedule(_ job: @escaping Job) {
        pending = job
        timer?.cancel()
        timer = Task { [delay, waiting] in
            await waiting(delay)
            guard !Task.isCancelled else { return }
            await self.kick()
        }
    }

    /// Write now, and wait for it — what leaving a project does, so the
    /// library it returns to is not showing yesterday.
    public func flush() async {
        timer?.cancel()
        timer = nil
        while pending != nil || writer != nil {
            kick()
            guard let writer else { break }
            await writer.value
        }
    }

    /// Drop what is owed but not yet started. A write already in the air is
    /// left to finish: aborting it half-way is worse than the extra row.
    public func cancel() {
        timer?.cancel()
        timer = nil
        pending = nil
    }

    /// Start the writer if there is something to write and nobody writing.
    private func kick() {
        guard writer == nil, pending != nil else { return }
        writer = Task { await self.drain() }
    }

    private func drain() async {
        // An edit that lands while a write is in the air is picked up by
        // the next turn of this loop rather than racing it.
        while let job = pending {
            pending = nil
            do {
                try await job()
                saves += 1
            } catch {
                // Offline, or a transient failure. The next edit retries,
                // and there is nothing useful to say to somebody mid-drag.
                failures += 1
            }
        }
        writer = nil
    }
}
