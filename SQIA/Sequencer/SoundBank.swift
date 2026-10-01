// Every sound the app knows, and the recordings it has on the phone.
//
// The list is the bundle's sounds with the `sounds` table laid over them —
// read from disk at once, then from the network once per launch. A sound
// made of recordings is not playable until they are downloaded and
// decoded; `prepare` does both, once, however many callers ask at the same
// time, and reports how far along it is in `progress`.

import Foundation
import Observation
import SQIACore

@MainActor
@Observable
final class SoundBank {
    static let shared = SoundBank()

    /// Every sound, hidden ones too, in picker order.
    private(set) var sounds: [Sound] = Sound.bundled
    /// 0…1 for each download under way.
    private(set) var progress: [Int: Double] = [:]
    /// Raised whenever the list changes, so whoever plays sounds can bring
    /// the ones in use up to date.
    @ObservationIgnored var onChange: (() -> Void)?

    @ObservationIgnored private let store = SoundStore(
        directory: SoundStore.defaultDirectory, downloader: SoundBank.downloader)

    private static var downloader: SoundStore.Downloader {
        #if DEBUG
            // `-slowSounds` stretches every file to half a second, so the
            // progress bar can be seen on a desk with a fast connection.
            if ProcessInfo.processInfo.arguments.contains("-slowSounds") {
                return { request, progress in
                    let data = try await SoundStore.urlSessionDownload(request) { _ in }
                    for step in 1...5 {
                        try await Task.sleep(for: .milliseconds(100))
                        progress(data.count * step / 5)
                    }
                    return data
                }
            }
        #endif
        return SoundStore.urlSessionDownload
    }
    @ObservationIgnored private var decoded: [Int: (folder: String, set: SampleSet)] = [:]
    @ObservationIgnored private var inFlight: [Int: Task<SampleSet, Error>] = [:]
    @ObservationIgnored private var refreshed = false

    /// The ones the picker offers.
    var offered: [Sound] { sounds.filter(\.visible) }

    func sound(_ id: Int) -> Sound? {
        sounds.first { $0.id == id }
    }

    /// Once a launch: what was last seen, straight away, then the network.
    func refreshIfNeeded() {
        guard !refreshed else { return }
        refreshed = true
        Task {
            apply(await store.cachedRows())
            guard let rows = try? await store.fetchRows() else { return }
            apply(rows)
            await store.prune(keeping: sounds.compactMap(\.samples))
        }
    }

    private func apply(_ rows: [SoundRow]) {
        let merged = SoundCatalog.merge(bundled: Sound.bundled, rows: rows)
        guard merged != sounds else { return }
        sounds = merged
        onChange?()
    }

    /// Whether the sound can play without waiting for anything.
    func isReady(_ sound: Sound) -> Bool {
        guard let manifest = sound.samples else { return true }
        return decoded[sound.id]?.folder == manifest.folder
    }

    /// The decoded recordings, if they are ready.
    func samples(for sound: Sound) -> SampleSet? {
        guard let manifest = sound.samples, let entry = decoded[sound.id],
            entry.folder == manifest.folder
        else { return nil }
        return entry.set
    }

    /// Downloads what is missing and decodes it. Nil for a sound with no
    /// recordings. A second call while the first is running waits for the
    /// same download.
    func prepare(_ sound: Sound) async throws -> SampleSet? {
        guard let manifest = sound.samples else { return nil }
        if let ready = samples(for: sound) { return ready }
        let id = sound.id

        let task: Task<SampleSet, Error>
        if let running = inFlight[id] {
            task = running
        } else {
            let store = store
            task = Task { [weak self] in
                let folder = try await store.download(manifest) { fraction in
                    Task { @MainActor in self?.report(id, fraction) }
                }
                // Four megabytes of WAV is not work for the main thread.
                let set = await Task.detached(priority: .userInitiated) {
                    SampleSet.load(manifest, from: folder)
                }.value
                guard let set else { throw SoundStore.Failure.unreadable }
                return set
            }
            inFlight[id] = task
        }

        do {
            let set = try await task.value
            decoded[id] = (manifest.folder, set)
            inFlight[id] = nil
            progress[id] = nil
            return set
        } catch {
            inFlight[id] = nil
            progress[id] = nil
            throw error
        }
    }

    private func report(_ id: Int, _ fraction: Double) {
        guard inFlight[id] != nil else { return }
        // Updates hop threads and can arrive out of order; the bar only
        // goes forward.
        progress[id] = max(progress[id] ?? 0, fraction)
    }
}
