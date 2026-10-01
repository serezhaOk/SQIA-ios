// The sounds designed in SQIA Lab.
//
// A sound is a preset file exactly as the Lab saves it ("sqia.sound",
// version 1): a Plaits model or a set of recordings, its knobs, and how far
// each knob may wander per note. The file is the whole definition.
//
// Sounds come from two places. A few ship in the bundle (`Sounds/`), so the
// app has them on its first launch and offline. The rest are published from
// the Lab to the `sounds` table and its storage bucket, and reach the app
// without a release — see `SoundCatalog` and `SoundStore`. Both kinds are
// named by the same number: the voice index a track stores in the project.
// The five original synths are 0…4; a sound is 5 or more, and a number is
// never given to a second sound, because projects in the database hold it.

import Foundation
import SQIASound

public struct Sound: Sendable, Identifiable, Equatable {
    /// The voice index a track stores.
    public let id: Int
    /// As it was saved in the Lab.
    public var name: String
    public var hint: String
    /// Parameter values and spreads by the core's parameter index.
    public var values: [Float]
    public var spreads: [Float]
    /// The recordings it plays, if it is made of them.
    public var samples: SampleManifest?
    /// Only for SQIA Plus.
    public var plus: Bool
    /// Where it sits in the picker; lower first.
    public var position: Int
    /// Hidden sounds are not offered, but projects that use one still play it.
    public var visible: Bool

    /// How long a step holds its note, in steps — what the Lab's pattern
    /// plays with unless told otherwise, and so what these were tuned to.
    public static let noteSteps = 0.5

    /// Lower case, like every sound's name in the app, whatever the Lab
    /// file was saved as.
    public var label: String { name.lowercased() }

    public init?(
        id: Int, preset: PresetFile, hint: String = "", samples: SampleManifest? = nil,
        plus: Bool = false, position: Int? = nil, visible: Bool = true
    ) {
        guard preset.format == "sqia.sound", id >= TrackVoice.firstSoundIndex else { return nil }
        self.id = id
        self.name = preset.name
        self.hint = hint
        self.samples = preset.source == "samples" ? samples : nil
        self.plus = plus
        self.position = position ?? id
        self.visible = visible

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
        for (key, entry) in preset.params {
            guard let i = keys[key] else { continue }
            values[i] = entry.value
            spreads[i] = entry.spread ?? 0
        }
        let engine = (0..<Int32(SQIA_ENGINE_COUNT)).first {
            String(cString: sqia_engine_key($0)) == preset.engine
        }
        values[Int(SQIA_PARAM_ENGINE.rawValue)] = Float(engine ?? 8)
        let modes = ["adsr": SQIA_AMP_ADSR, "lpg": SQIA_AMP_LPG, "ping": SQIA_AMP_PING]
        values[Int(SQIA_PARAM_AMP_MODE.rawValue)] = Float((modes[preset.ampMode] ?? SQIA_AMP_LPG).rawValue)
        values[Int(SQIA_PARAM_SOURCE.rawValue)] = Float(
            (preset.source == "samples" ? SQIA_SOURCE_SAMPLES : SQIA_SOURCE_PLAITS).rawValue)
        self.values = values
        self.spreads = spreads
    }

    /// Hand every knob to a synth. Recordings travel separately, once they
    /// are on the phone.
    public func apply(to synth: OpaquePointer) {
        for i in values.indices {
            sqia_synth_set_param(synth, Int32(i), values[i])
            sqia_synth_set_spread(synth, Int32(i), spreads[i])
        }
    }

    /// The ones in the bundle. Append-only, and every number here is taken
    /// for good.
    private static let shipped: [(id: Int, file: String, hint: String)] = [
        (5, "BEES", "Buzzing analog, struck"),
        (6, "Barefeet", "Soft filtered pluck"),
        (7, "Dancing flower", "Wave terrain, falling"),
        (8, "Garedener", "Phase distortion, swept"),
        (9, "Samurai Walk", "Inharmonic string"),
    ]

    public static let bundled: [Sound] = shipped.compactMap { entry in
        guard
            let url = Bundle.module.url(
                forResource: entry.file, withExtension: "json", subdirectory: "Sounds"),
            let data = try? Data(contentsOf: url),
            let preset = try? JSONDecoder().decode(PresetFile.self, from: data)
        else { return nil }
        return Sound(id: entry.id, preset: preset, hint: entry.hint)
    }
}

/// The Lab's preset file, as it is saved and as the `sounds` table holds it.
public struct PresetFile: Codable, Sendable, Equatable {
    public struct Value: Codable, Sendable, Equatable {
        public var value: Float
        public var spread: Float?
    }
    public var format: String
    public var name: String
    public var engine: String
    public var ampMode: String
    public var source: String?
    public var samples: String?
    public var params: [String: Value]
}

/// Which recordings a sound plays and how they lie across the keys — the
/// Lab's `set.json`, plus where the files are kept and how big they are, so
/// a download can say how far along it is.
public struct SampleManifest: Codable, Sendable, Equatable {
    public struct Entry: Codable, Sendable, Equatable {
        public var file: String
        public var root: Float?
        public var bytes: Int?

        public init(file: String, root: Float? = nil, bytes: Int? = nil) {
            self.file = file
            self.root = root
            self.bytes = bytes
        }
    }

    /// The folder in the `sounds` bucket. A new upload gets a new folder,
    /// so a phone never mistakes old files for new ones.
    public var folder: String
    /// "pitched" or "kit".
    public var mode: String
    public var samples: [Entry]

    public init(folder: String, mode: String, samples: [Entry]) {
        self.folder = folder
        self.mode = mode
        self.samples = samples
    }

    public var totalBytes: Int { samples.reduce(0) { $0 + ($1.bytes ?? 0) } }
}

/// A sound's recordings, decoded and ready to hand to a synth.
public struct SampleSet: Sendable {
    public struct Recording: Sendable {
        public var audio: WaveFile
        public var root: Float
    }

    public let kit: Bool
    public let recordings: [Recording]

    /// Reads every recording the manifest names from a folder. Nil if any
    /// is missing or unreadable — half a handpan is not a handpan.
    public static func load(_ manifest: SampleManifest, from folder: URL) -> SampleSet? {
        var recordings: [Recording] = []
        for entry in manifest.samples {
            guard let bytes = try? Data(contentsOf: folder.appendingPathComponent(entry.file)),
                let audio = WaveFile(data: bytes)
            else { return nil }
            recordings.append(Recording(audio: audio, root: entry.root ?? 60))
        }
        guard !recordings.isEmpty else { return nil }
        return SampleSet(kit: manifest.mode == "kit", recordings: recordings)
    }

    /// A fresh copy for a synth, laid out the way the Lab lays it out. The
    /// synth owns it from then on.
    public func make() -> OpaquePointer? {
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

/// What a track plays: one of the five original synths, or a sound. Stored
/// as one index — the synths keep 0…4, a sound is its own id.
public enum TrackVoice: Sendable, Hashable {
    case synth(SynthPreset)
    case sound(Int)

    public static let firstSoundIndex = SynthPreset.allCases.count

    /// A number past the synths is a sound even when this phone has not
    /// heard of it yet: the catalogue may still be on its way, and the track
    /// should play it once it arrives rather than turn into something else.
    public init(index: Int) {
        if let preset = SynthPreset(rawValue: index) {
            self = .synth(preset)
        } else if index >= Self.firstSoundIndex {
            self = .sound(index)
        } else {
            self = .synth(.reverie)
        }
    }

    public var index: Int {
        switch self {
        case .synth(let preset): return preset.rawValue
        case .sound(let id): return id
        }
    }

    public var preset: SynthPreset? {
        if case .synth(let preset) = self { return preset }
        return nil
    }
}
