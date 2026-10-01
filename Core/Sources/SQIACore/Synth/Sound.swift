// The sounds designed in SQIA Lab.
//
// A sound is a preset file exactly as the Lab saves it ("sqia.sound",
// version 1): a Plaits model, its knobs, and how far each knob may wander
// per note. The file is the whole definition — nothing about the sound is
// written here but its place in the list and one line for the picker.
//
// A sound made of recordings names a folder under `Sounds/samples/`, which
// holds the recordings and a `set.json` saying how they lie across the keys
// — the same folder the Lab played them from.
//
// Adding one: save it in the Lab, copy the .json into `Sounds/` (and its
// sample folder into `Sounds/samples/`), and append it below. Never reorder
// or remove — a track stores its voice as an index, and that index is in the
// database.

import Foundation
import SQIASound

public struct Sound: Sendable, Identifiable {
    /// Position in `library`.
    public let id: Int
    /// As it was saved in the Lab.
    public let name: String
    public let hint: String
    /// Parameter values and spreads by the core's parameter index.
    public let values: [Float]
    public let spreads: [Float]
    /// The folder of recordings it plays, if it is made of them.
    public let sampleSet: String?

    /// How long a step holds its note, in steps — what the Lab's pattern
    /// plays with unless told otherwise, and so what these were tuned to.
    public static let noteSteps = 0.5

    /// Lower case, like every sound's name in the app, whatever the Lab
    /// file was saved as.
    public var label: String { name.lowercased() }

    /// Hand every knob to a synth, and its recordings if it has any.
    public func apply(to synth: OpaquePointer) {
        for i in values.indices {
            sqia_synth_set_param(synth, Int32(i), values[i])
            sqia_synth_set_spread(synth, Int32(i), spreads[i])
        }
        if let name = sampleSet, let recordings = SampleSet.named(name) {
            sqia_synth_set_samples(synth, recordings.make())
        }
    }

    /// Append-only.
    private static let catalogue: [(file: String, hint: String)] = [
        ("BEES", "Buzzing analog, struck"),
        ("Barefeet", "Soft filtered pluck"),
        ("Dancing flower", "Wave terrain, falling"),
        ("Garedener", "Phase distortion, swept"),
        ("Samurai Walk", "Inharmonic string"),
        ("Handpan", "Recorded handpan"),
    ]

    public static let library: [Sound] = catalogue.enumerated().compactMap { index, entry in
        guard
            let url = Bundle.module.url(
                forResource: entry.file, withExtension: "json", subdirectory: "Sounds"),
            let data = try? Data(contentsOf: url)
        else { return nil }
        return Sound(id: index, hint: entry.hint, json: data)
    }

    init?(id: Int, hint: String, json: Data) {
        guard let file = try? JSONDecoder().decode(File.self, from: json),
            file.format == "sqia.sound"
        else { return nil }
        self.id = id
        self.name = file.name
        self.hint = hint
        self.sampleSet = file.source == "samples" ? file.samples : nil

        let count = Int(SQIA_PARAM_COUNT.rawValue)
        var values = [Float](repeating: 0, count: count)
        var spreads = [Float](repeating: 0, count: count)
        var keys: [String: Int] = [:]
        for i in 0..<count {
            var info = SQIAParamInfo()
            sqia_param_info(Int32(i), &info)
            values[i] = info.default_value
            keys[String(cString: info.key)] = i
        }
        for (key, entry) in file.params {
            guard let i = keys[key] else { continue }
            values[i] = entry.value
            spreads[i] = entry.spread ?? 0
        }
        let engine = (0..<Int32(SQIA_ENGINE_COUNT)).first {
            String(cString: sqia_engine_key($0)) == file.engine
        }
        values[Int(SQIA_PARAM_ENGINE.rawValue)] = Float(engine ?? 8)
        let modes = ["adsr": SQIA_AMP_ADSR, "lpg": SQIA_AMP_LPG, "ping": SQIA_AMP_PING]
        values[Int(SQIA_PARAM_AMP_MODE.rawValue)] = Float((modes[file.ampMode] ?? SQIA_AMP_LPG).rawValue)
        values[Int(SQIA_PARAM_SOURCE.rawValue)] = Float(
            (file.source == "samples" ? SQIA_SOURCE_SAMPLES : SQIA_SOURCE_PLAITS).rawValue)
        self.values = values
        self.spreads = spreads
    }

    private struct File: Decodable {
        struct Value: Decodable {
            var value: Float
            var spread: Float?
        }
        var format: String
        var name: String
        var engine: String
        var ampMode: String
        var source: String?
        var samples: String?
        var params: [String: Value]
    }
}

/// A folder of recordings under `Sounds/samples/`, read once and kept, so a
/// mixer rebuilt after a route change does not decode it all again.
struct SampleSet: Sendable {
    struct Recording: Sendable {
        var audio: WaveFile
        var root: Float
    }

    let kit: Bool
    let recordings: [Recording]

    private struct Description: Decodable {
        struct Entry: Decodable {
            var file: String
            var root: Float?
        }
        var mode: String
        var samples: [Entry]
    }

    private static let cache = SampleSetCache()

    static func named(_ name: String) -> SampleSet? {
        cache.get(name) ?? {
            guard let set = load(name) else { return nil }
            cache.put(name, set)
            return set
        }()
    }

    private static func load(_ name: String) -> SampleSet? {
        guard
            let folder = Bundle.module.resourceURL?
                .appendingPathComponent("Sounds/samples", isDirectory: true)
                .appendingPathComponent(name, isDirectory: true),
            let data = try? Data(contentsOf: folder.appendingPathComponent("set.json")),
            let description = try? JSONDecoder().decode(Description.self, from: data)
        else { return nil }
        let recordings = description.samples.compactMap { entry -> Recording? in
            guard let bytes = try? Data(contentsOf: folder.appendingPathComponent(entry.file)),
                let audio = WaveFile(data: bytes)
            else { return nil }
            return Recording(audio: audio, root: entry.root ?? 60)
        }
        guard !recordings.isEmpty else { return nil }
        return SampleSet(kit: description.mode == "kit", recordings: recordings)
    }

    /// A fresh copy for the synth, laid out the way the Lab lays it out.
    func make() -> OpaquePointer? {
        guard let set = sqia_samples_create() else { return nil }
        for recording in recordings {
            let audio = recording.audio
            audio.left.withUnsafeBufferPointer { left in
                if let right = audio.right {
                    right.withUnsafeBufferPointer { right in
                        _ = sqia_samples_add(
                            set, left.baseAddress, right.baseAddress, Int32(audio.frames),
                            audio.sampleRate)
                    }
                } else {
                    _ = sqia_samples_add(set, left.baseAddress, nil, Int32(audio.frames), audio.sampleRate)
                }
            }
        }
        sqia_samples_lay_out(set, kit ? SQIA_LAYOUT_KIT : SQIA_LAYOUT_PITCHED, recordings.map(\.root))
        return set
    }
}

private final class SampleSetCache: @unchecked Sendable {
    private let lock = NSLock()
    private var sets: [String: SampleSet] = [:]

    func get(_ name: String) -> SampleSet? {
        lock.lock()
        defer { lock.unlock() }
        return sets[name]
    }

    func put(_ name: String, _ set: SampleSet) {
        lock.lock()
        sets[name] = set
        lock.unlock()
    }
}

/// What a track plays: one of the five original synths, or a sound from the
/// Lab. Stored as one index — the synths keep 0…4, the sounds follow.
public enum TrackVoice: Sendable, Hashable {
    case synth(SynthPreset)
    case sound(Int)

    public static let firstSoundIndex = SynthPreset.allCases.count

    public init(index: Int) {
        if let preset = SynthPreset(rawValue: index) {
            self = .synth(preset)
        } else if Sound.library.indices.contains(index - Self.firstSoundIndex) {
            self = .sound(index - Self.firstSoundIndex)
        } else {
            // A voice this build does not know — from a newer one, say.
            self = .synth(.reverie)
        }
    }

    public var index: Int {
        switch self {
        case .synth(let preset): return preset.rawValue
        case .sound(let i): return Self.firstSoundIndex + i
        }
    }

    public var label: String {
        switch self {
        case .synth(let preset): return preset.label
        case .sound(let i): return Sound.library[i].label
        }
    }

    public var hint: String {
        switch self {
        case .synth(let preset): return preset.hint
        case .sound(let i): return Sound.library[i].hint
        }
    }

    public var preset: SynthPreset? {
        if case .synth(let preset) = self { return preset }
        return nil
    }
}
