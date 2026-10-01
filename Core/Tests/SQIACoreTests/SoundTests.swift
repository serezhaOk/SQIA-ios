// The Lab's sounds, as SQIA carries them: the bundle's, the table's, and
// the recordings that come down to the phone.

import Foundation
import Testing

@testable import SQIACore

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

private let preset = PresetFile(
    format: "sqia.sound", name: "Glass", engine: "modal", ampMode: "ping", source: nil, samples: nil,
    params: ["harmonics": .init(value: 0.3, spread: 0.1)])

private let sampled = PresetFile(
    format: "sqia.sound", name: "Handpan", engine: "virtual_analog", ampMode: "ping",
    source: "samples", samples: "hang it", params: [:])

private func manifest(_ folder: String, _ sizes: [Int]) -> SampleManifest {
    SampleManifest(
        folder: folder, mode: "pitched",
        samples: sizes.enumerated().map {
            .init(file: "\($0.offset).wav", root: Float(60 + $0.offset), bytes: $0.element)
        })
}

@Suite("Lab sounds")
struct SoundTests {
    @Test("The bundle's sounds read, with the numbers they shipped under")
    func bundled() {
        #expect(Sound.bundled.map(\.name) == [
            "BEES", "Barefeet", "Dancing flower", "Garedener", "Samurai Walk",
        ])
        #expect(Sound.bundled.map(\.id) == [5, 6, 7, 8, 9])
        #expect(Sound.bundled.allSatisfy { !$0.plus && $0.visible && $0.samples == nil })
    }

    @Test("A sound keeps what the file says")
    func values() throws {
        let string = try #require(Sound.bundled.first { $0.name == "Samurai Walk" })
        // "string" is Plaits' model 19; amp mode "lpg" is 1.
        #expect(string.values[0] == 19)
        #expect(string.values[9] == 1)
        let bees = try #require(Sound.bundled.first { $0.name == "BEES" })
        #expect(bees.values[9] == 2)  // ping
    }

    @Test("Voice indices: the five synths keep theirs, everything after is a sound")
    func voiceIndex() {
        #expect(TrackVoice(index: 0) == .synth(.reverie))
        #expect(TrackVoice(index: 4) == .synth(.machine))
        #expect(TrackVoice(index: 5) == .sound(5))
        // A sound this phone has not heard of yet stays that sound, so it
        // plays once the catalogue brings it.
        #expect(TrackVoice(index: 99) == .sound(99))
        #expect(TrackVoice.sound(10).index == 10)
        #expect(TrackVoice(index: -3) == .synth(.reverie))
    }

    @Test("A Plus sound is for Plus")
    func plus() throws {
        var sound = try #require(Sound(id: 10, preset: preset))
        #expect(Access.free.plays(sound))
        sound.plus = true
        #expect(!Access.free.plays(sound))
        #expect(Access.plus.plays(sound))
        #expect(Access.free.plays(nil))
    }

    @Test("The table adds sounds, and re-labels, hides or locks the bundle's")
    func merge() {
        let rows = [
            SoundRow(
                id: 10, name: "Handpan", hint: "Recorded handpan", preset: sampled,
                samples: manifest("hang-1", [10, 20]), position: 3, plus: true),
            // No preset: only the metadata of a bundled sound.
            SoundRow(id: 6, name: "Bare Feet", hint: "Renamed", position: 100, visible: false),
            // Needs a core this build does not have.
            SoundRow(id: 11, name: "Future", preset: preset, position: 1, minCore: 99),
            // A metadata row for a sound nobody has.
            SoundRow(id: 12, name: "Ghost", position: 2),
        ]
        let sounds = SoundCatalog.merge(bundled: Sound.bundled, rows: rows)
        #expect(sounds.map(\.id) == [10, 5, 7, 8, 9, 6])
        let handpan = sounds[0]
        #expect(handpan.plus && handpan.samples?.folder == "hang-1" && handpan.hint == "Recorded handpan")
        #expect(sounds.last?.name == "Bare Feet" && sounds.last?.visible == false)
    }

    @Test("A sound note plays through the mixer, at the device's rate", arguments: [48_000.0, 44_100.0])
    func mixerPlaysSound(rate: Double) {
        let mixer = AudioMixer(sampleRate: rate)
        for (i, sound) in Sound.bundled.enumerated() {
            mixer.schedule(
                AudioEvent.sound(
                    SoundNote(sound: sound.id, midi: 57, velocity: 0.9, seconds: 0.1),
                    at: Int64(Double(i) * 0.5 * rate)))
        }
        let left = render(mixer, seconds: 3, rate: rate)
        #expect(left.allSatisfy { $0.isFinite })
        for (i, sound) in Sound.bundled.enumerated() {
            let start = Int(Double(i) * 0.5 * rate)
            let window = left[start..<(start + Int(0.3 * rate))]
            #expect((window.map(abs).max() ?? 0) > 0.01, "\(sound.name) is silent")
        }
    }

    @Test("A sound arriving while the mixer runs plays from then on; before, its notes are dropped")
    func installLater() throws {
        let mixer = AudioMixer(sampleRate: 48_000)
        let late = try #require(Sound(id: 40, preset: preset))
        #expect(!mixer.isInstalled(late))
        mixer.schedule(AudioEvent.sound(SoundNote(sound: 40, midi: 60, velocity: 1, seconds: 0.1), at: 0))
        #expect(render(mixer, seconds: 0.3, rate: 48_000).map(abs).max() == 0)

        mixer.install(late, samples: nil)
        #expect(mixer.isInstalled(late))
        mixer.schedule(
            AudioEvent.sound(
                SoundNote(sound: 40, midi: 60, velocity: 1, seconds: 0.1), at: mixer.currentFrame))
        #expect((render(mixer, seconds: 0.3, rate: 48_000).map(abs).max() ?? 0) > 0.01)
    }

    @Test("A sampled sound is installed only with its recordings")
    func installWithSamples() throws {
        let mixer = AudioMixer(sampleRate: 48_000)
        let tone = (0..<9_600).map { Float(0.5 * sin(2 * .pi * 440 * Double($0) / 48_000)) }
        let set = SampleSet(
            kit: false,
            recordings: [.init(audio: WaveFile(sampleRate: 48_000, left: tone, right: nil), root: 69)])
        let handpan = try #require(
            Sound(id: 10, preset: sampled, samples: manifest("hang-1", [19_200])))
        mixer.install(handpan, samples: nil)
        #expect(!mixer.isInstalled(handpan), "knobs alone are not the sound")
        mixer.install(handpan, samples: set)
        #expect(mixer.isInstalled(handpan))
        mixer.schedule(AudioEvent.sound(SoundNote(sound: 10, midi: 69, velocity: 1, seconds: 0.1), at: 0))
        #expect((render(mixer, seconds: 0.1, rate: 48_000).map(abs).max() ?? 0) > 0.05)
    }

    private func render(_ mixer: AudioMixer, seconds: Double, rate: Double) -> [Float] {
        let frames = Int(seconds * rate)
        var left = [Float](repeating: 0, count: frames)
        var right = left
        left.withUnsafeMutableBufferPointer { l in
            right.withUnsafeMutableBufferPointer { r in
                var offset = 0
                while offset < frames {
                    let n = min(512, frames - offset)
                    mixer.render(
                        frameCount: n, left: l.baseAddress! + offset, right: r.baseAddress! + offset)
                    offset += n
                }
            }
        }
        return left
    }
}

@Suite("Sound store")
struct SoundStoreTests {
    private func directory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("sounds-\(UUID().uuidString)")
    }

    @Test("The table is read with the publishable key and kept for offline")
    func rows() async throws {
        let dir = directory()
        let row = SoundRow(
            id: 10, name: "Handpan", preset: sampled, samples: manifest("hang-1", [3]), plus: true)
        let body = try JSONEncoder().encode([row])
        let store = SoundStore(
            key: "publishable", directory: dir,
            transport: { request in
                #expect(request.url!.absoluteString.contains("/rest/v1/sounds?select=*"))
                #expect(request.value(forHTTPHeaderField: "apikey") == "publishable")
                return (
                    body,
                    HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                )
            },
            downloader: { _, _ in Data() })
        #expect(await store.cachedRows().isEmpty)
        #expect(try await store.fetchRows() == [row])
        #expect(await store.cachedRows() == [row])

        let offline = SoundStore(
            directory: dir, transport: { _ in throw URLError(.notConnectedToInternet) },
            downloader: { _, _ in Data() })
        #expect(await offline.cachedRows() == [row])
        await #expect(throws: (any Error).self) { try await offline.fetchRows() }
    }

    @Test("Recordings come down once, with the bar moving all the way to 1")
    func download() async throws {
        let dir = directory()
        let set = manifest("hang 1", [4, 6])
        let fetched = Counter()
        let store = SoundStore(
            directory: dir, transport: { _ in throw URLError(.badURL) },
            downloader: { request, progress in
                fetched.add()
                // The folder's space survives the trip as %20.
                #expect(request.url!.absoluteString.contains("/storage/v1/object/public/sounds/hang%201/"))
                let size = request.url!.lastPathComponent == "0.wav" ? 4 : 6
                progress(size / 2)
                progress(size)
                return Data(repeating: 1, count: size)
            })
        let seen = Seen()
        #expect(await !store.isDownloaded(set))
        try await store.download(set) { seen.add($0) }
        #expect(await store.isDownloaded(set))
        #expect(fetched.value == 2)
        #expect(seen.values.first == 0 && seen.values.last == 1)
        #expect(seen.values == seen.values.sorted(), "the bar never goes backwards")

        // Already here: nothing is fetched again.
        try await store.download(set)
        #expect(fetched.value == 2)

        await store.prune(keeping: [])
        #expect(await !store.isDownloaded(set))
    }

    @Test("A short file is not taken for a whole one")
    func incomplete() async throws {
        let store = SoundStore(
            directory: directory(), transport: { _ in throw URLError(.badURL) },
            downloader: { _, _ in Data(repeating: 0, count: 3) })
        let set = manifest("short", [10])
        await #expect(throws: SoundStore.Failure.incomplete) { try await store.download(set) }
        #expect(await !store.isDownloaded(set))
    }
}

private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func add() {
        lock.lock()
        count += 1
        lock.unlock()
    }
    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }
}

private final class Seen: @unchecked Sendable {
    private let lock = NSLock()
    private var list: [Double] = []
    func add(_ v: Double) {
        lock.lock()
        list.append(v)
        lock.unlock()
    }
    var values: [Double] {
        lock.lock()
        defer { lock.unlock() }
        return list
    }
}

@Suite("WAV files")
struct WaveFileTests {
    private func wav(format: Int, bits: Int, channels: Int, rate: Int, body: [UInt8]) -> Data {
        func le(_ v: Int, _ n: Int) -> [UInt8] { (0..<n).map { UInt8((v >> (8 * $0)) & 0xFF) } }
        var fmt = le(format, 2) + le(channels, 2) + le(rate, 4)
        fmt += le(rate * channels * bits / 8, 4) + le(channels * bits / 8, 2) + le(bits, 2)
        var chunks: [UInt8] = Array("WAVE".utf8)
        // An unknown chunk of odd length first, to exercise the padding.
        chunks += Array("LIST".utf8) + le(3, 4) + [1, 2, 3, 0]
        chunks += Array("fmt ".utf8) + le(fmt.count, 4) + fmt
        chunks += Array("data".utf8) + le(body.count, 4) + body
        return Data(Array("RIFF".utf8) + le(chunks.count, 4) + chunks)
    }

    @Test("16-bit mono")
    func sixteen() throws {
        // 0, +half, −full
        let file = try #require(
            WaveFile(
                data: wav(format: 1, bits: 16, channels: 1, rate: 44_100, body: [0, 0, 0, 0x40, 0, 0x80])))
        #expect(file.sampleRate == 44_100)
        #expect(file.left == [0, 0.5, -1])
        #expect(file.right == nil)
    }

    @Test("24-bit stereo")
    func twentyFour() throws {
        // L = +half, R = −half
        let file = try #require(
            WaveFile(
                data: wav(format: 1, bits: 24, channels: 2, rate: 48_000, body: [0, 0, 0x40, 0, 0, 0xC0])))
        #expect(file.left == [0.5])
        #expect(file.right == [-0.5])
    }

    @Test("Not a WAV")
    func garbage() {
        #expect(WaveFile(data: Data("hello".utf8)) == nil)
    }
}
