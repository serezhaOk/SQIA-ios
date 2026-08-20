// Decoded samples, loaded once and kept.
//
// The render thread reads straight out of these buffers, so they must not
// move or be freed while a note is sounding. Rather than reference-count
// them on the audio thread, the library allocates each one once and never
// releases it — the whole set is 12 MB, and the web app's cache never evicts
// either.

import AVFoundation
import SQIACore

final class SampleLibrary {
    static let shared = SampleLibrary()

    private var cache: [String: SampleRef] = [:]
    /// Held so the allocations stay reachable for the life of the process.
    private var storage: [UnsafeMutableBufferPointer<Float>] = []
    private let lock = NSLock()

    private init() {}

    /// Decode a sample from the bundle, or hand back the one already decoded.
    /// Call this off the audio thread — loading a file is not fast.
    func sample(named name: String) -> SampleRef? {
        lock.lock()
        defer { lock.unlock() }

        if let cached = cache[name] { return cached }
        guard let decoded = decode(name) else { return nil }
        cache[name] = decoded
        return decoded
    }

    /// Whether a sample is already in memory — the caller can then use it
    /// without risking a decode on a thread that cannot afford one.
    func isLoaded(_ name: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return cache[name] != nil
    }

    /// The decoded sample if it is already in memory, and nothing if it is
    /// not. Never reads a file, so it is safe to call from anywhere — every
    /// stroke of a finger goes through here.
    func cached(_ name: String) -> SampleRef? {
        lock.lock()
        defer { lock.unlock() }
        return cache[name]
    }

    private func decode(_ name: String) -> SampleRef? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "wav") else {
            assertionFailure("sample \(name).wav is missing from the bundle")
            return nil
        }

        do {
            let file = try AVAudioFile(forReading: url)
            let format = file.processingFormat
            let frameCount = AVAudioFrameCount(file.length)
            guard frameCount > 0,
                let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)
            else { return nil }

            try file.read(into: buffer)
            guard let channels = buffer.floatChannelData else { return nil }

            let frames = Int(buffer.frameLength)
            let channelCount = Int(format.channelCount)

            let left = copy(channels[0], count: frames)
            // Anything beyond two channels is not something this app ships.
            let right = channelCount > 1 ? copy(channels[1], count: frames) : nil

            return SampleRef(
                left: UnsafePointer(left),
                right: right.map { UnsafePointer($0) },
                frameCount: frames,
                sampleRate: format.sampleRate
            )
        } catch {
            assertionFailure("could not decode \(name).wav: \(error)")
            return nil
        }
    }

    private func copy(_ source: UnsafePointer<Float>, count: Int) -> UnsafeMutablePointer<Float> {
        let buffer = UnsafeMutableBufferPointer<Float>.allocate(capacity: count)
        buffer.baseAddress!.update(from: source, count: count)
        storage.append(buffer)
        return buffer.baseAddress!
    }
}

/// The built-in sample set, in the order the web app lists it.
///
/// The web app has the whole list commented out — the voice cycle is synths
/// only for now — and this mirrors that: the files ship, the playback path
/// works, and turning them back on is uncommenting a list in both places.
enum SampleSet {
    struct Definition {
        let file: String
        let label: String
        /// Samples are recorded in C, so this only moves for one in a
        /// different octave.
        let baseMidi: Int = Music.defaultBaseMidi
    }

    static let all: [Definition] = [
        // Definition(file: "bell-kalimbox", label: "KALIMBOX"),
        // Definition(file: "keys-synth", label: "KEYS SYNTH"),
        // Definition(file: "grand-piano-low", label: "PIANO LOW"),
        // Definition(file: "grand-piano-high", label: "PIANO HIGH"),
        // Definition(file: "horn-synth", label: "HORN SYNTH"),
        // Definition(file: "ikembe", label: "IKEMBE"),
        // Definition(file: "bell-evolving", label: "EVOLVING"),
        // Definition(file: "bell-lovely", label: "LOVELY"),
        // Definition(file: "bell-toy-piano", label: "TOY PIANO"),
        // Definition(file: "bell-ring", label: "RING BELL"),
        // Definition(file: "synth-round-five", label: "ROUND FIVE"),
        // Definition(file: "westafrica-ngona", label: "NGONA"),
        // Definition(file: "bells-agogo", label: "AGOGO"),
        // Definition(file: "cowbell", label: "COWBELL"),
        // Definition(file: "conga-low", label: "CONGA"),
        // Definition(file: "bongo-low", label: "BONGO"),
    ]
}
