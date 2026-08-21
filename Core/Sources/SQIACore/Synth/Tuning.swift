// The numbers that shape each voice, as data rather than as literals.
//
// Every preset rolls its values fresh per note out of a range — that is what
// "randomness in a frame" means here — so a knob is not a value but the
// frame itself: a low end and a high end. Narrow one and the preset becomes
// consistent; slide both and its character moves.
//
// There are two named sets. `Tuning.web` is the web's numbers to the digit,
// held down by tests against the literals they replaced — it is the
// reference, and the panel can always return to it. `Tuning.tuned` is what
// the app opens on: the same frame, moved where the owner's ear took it
// after listening. Every departure is one somebody made on purpose, and the
// two being separate is what keeps that legible.

import Foundation

/// A low and a high end. A knob that is really one value keeps both the
/// same, which is also how a range is narrowed to a point.
public struct TunableRange: Codable, Sendable, Equatable {
    public var low: Double
    public var high: Double

    public init(_ low: Double, _ high: Double) {
        self.low = low
        self.high = high
    }

    public init(_ value: Double) {
        self.init(value, value)
    }

    /// Ordered, whichever way round the handles were left.
    public var lower: Double { min(low, high) }
    public var upper: Double { max(low, high) }
    public var isSingle: Bool { low == high }
}

/// Everything the panel can move.
///
/// Raw values are the storage keys, so they are spelled out and never
/// renamed — a saved tuning has to keep meaning what it meant.
public enum TuningKnob: String, CaseIterable, Codable, Sendable {
    // REVERIE
    case reverieRelease
    case reverieSlowAttackChance
    case reverieSlowAttack
    case reverieDetune
    case reverieLevel

    // KALIMBA
    case kalimbaResonance
    case kalimbaDampening
    case kalimbaAttackNoise
    case kalimbaLowpass
    case kalimbaLevel

    // RHODES
    case rhodesModulationIndex
    case rhodesModulationDecay
    case rhodesModulationSustain
    case rhodesTremoloDepth
    case rhodesLevel

    // ACID
    case acidResonance
    case acidAccentResonance
    case acidBaseCutoff
    case acidOctaves
    case acidSweep
    case acidLevel

    // MACHINE
    case machineKickPitchStart
    case machineKickPitchDecay
    case machineKickLevel
    case machineSnareBandpass
    case machineMetalLevel
    case machineFollowsKey
    case machineSendHighpass
    case machineDelayWet

    // The shared room.
    case reverbDecay
    case reverbPreDelay
    case reverbDamping
}

/// What a knob means, for the panel to lay out and label.
public struct TuningSpec: Sendable {
    public enum Unit: Sendable, Equatable {
        case seconds
        case hertz
        case decibels
        case cents
        case ratio
        case chance
        /// On or off. The panel draws a switch for it.
        case flag

        public func format(_ value: Double) -> String {
            switch self {
            case .seconds:
                return value < 0.1
                    ? String(format: "%.0f ms", value * 1000)
                    : String(format: "%.2f s", value)
            case .hertz:
                return value >= 1000
                    ? String(format: "%.1f kHz", value / 1000)
                    : String(format: "%.0f Hz", value)
            case .decibels: return String(format: "%+.1f dB", value)
            case .cents: return String(format: "±%.0f ¢", value)
            case .ratio: return String(format: "%.2f", value)
            case .chance: return String(format: "%.0f%%", value * 100)
            case .flag: return value >= 0.5 ? "On" : "Off"
            }
        }
    }

    public let knob: TuningKnob
    /// Which preset it belongs to; nil for the shared room.
    public let preset: SynthPreset?
    public let label: String
    /// One line on what moving it does to the sound.
    public let detail: String
    /// How far the slider travels — wider than the web's range, so there is
    /// somewhere to go.
    public let bounds: ClosedRange<Double>
    public let unit: Unit

    /// True when the knob is a single value rather than a frame to roll in.
    public var isSingle: Bool { Tuning.web[knob].isSingle }
}

public struct Tuning: Codable, Sendable, Equatable {
    private var values: [TuningKnob: TunableRange]

    public init(_ values: [TuningKnob: TunableRange] = [:]) {
        self.values = values
    }

    /// A knob's frame, falling back to the web's if it was never set — so a
    /// tuning saved before a knob existed still loads.
    public subscript(knob: TuningKnob) -> TunableRange {
        get { values[knob] ?? Self.defaults[knob] ?? TunableRange(0) }
        set { values[knob] = newValue }
    }

    public var isWeb: Bool { self == .web }
    /// Whether anything has been moved from what the app opens on.
    public var isDefault: Bool { self == .tuned }

    public mutating func reset(_ knob: TuningKnob) {
        self[knob] = Self.tuned[knob]
    }

    public mutating func resetAll() {
        self = .tuned
    }

    /// Back to the web's own numbers, for hearing what was moved away from.
    public mutating func resetToWeb() {
        self = .web
    }

    // ------------------------------------------------------------ rolling --

    /// Roll inside a knob's frame. A frame narrowed to a point spends a
    /// value from the stream all the same, so the sequence every preset
    /// draws from does not shift when a knob is pinned.
    public func value(_ knob: TuningKnob, using random: RandomSource) -> Double {
        let frame = self[knob]
        return random.value(frame.low, frame.high)
    }

    /// The same, scaled — for the handful of places the web multiplies a
    /// rolled value by something else.
    public func chance(_ knob: TuningKnob, using random: RandomSource) -> Bool {
        random.chance(self[knob].lower)
    }

    /// A knob that is a switch rather than a frame.
    public func isOn(_ knob: TuningKnob) -> Bool { self[knob].lower >= 0.5 }

    // ----------------------------------------------------------- defaults --

    /// The web's numbers, kept as the reference they are: the parity tests
    /// measure against these, and the panel can always return to them.
    public static let web = Tuning(defaults)

    /// What the app opens on — the web's frame, moved where the owner's ear
    /// took it. Everything not listed here is still the web's.
    ///
    /// The shape of the decisions is worth keeping legible. RHODES lost most
    /// of its modulation and gained a slower bell, which is what took it
    /// from digital back towards struck. MACHINE's kick starts lower and
    /// sits louder, so it reads as weight rather than as a pitch. ACID's
    /// resonance was pulled open at the bottom and pushed up at the top, so
    /// the squelch became something that happens rather than something that
    /// is always on. And the room is less than half as long and brighter,
    /// which is this reverb being asked to sound less like a hall.
    public static let tuned: Tuning = {
        var tuning = Tuning(defaults)

        tuning[.reverieSlowAttackChance] = TunableRange(0.575)
        tuning[.reverieSlowAttack] = TunableRange(0.005, 0.35)
        tuning[.reverieDetune] = TunableRange(7.8)

        tuning[.kalimbaResonance] = TunableRange(0.715, 0.995)
        tuning[.kalimbaDampening] = TunableRange(200, 5114)
        tuning[.kalimbaAttackNoise] = TunableRange(0.05, 1.5)
        tuning[.kalimbaLowpass] = TunableRange(1945, 8090)

        tuning[.rhodesModulationIndex] = TunableRange(0, 8.02)
        tuning[.rhodesModulationDecay] = TunableRange(0.757, 1.709)
        tuning[.rhodesModulationSustain] = TunableRange(0, 0.322)
        tuning[.rhodesTremoloDepth] = TunableRange(0, 0.432)
        tuning[.rhodesLevel] = TunableRange(-0.69)

        tuning[.acidResonance] = TunableRange(0, 14.49)
        tuning[.acidAccentResonance] = TunableRange(5.08, 11.82)
        tuning[.acidBaseCutoff] = TunableRange(90.54, 275.68)
        tuning[.acidOctaves] = TunableRange(1.82, 2.865)
        tuning[.acidSweep] = TunableRange(0.345, 1.174)
        tuning[.acidLevel] = TunableRange(-16)

        tuning[.machineKickPitchStart] = TunableRange(2.44, 4.78)
        tuning[.machineKickPitchDecay] = TunableRange(0.02, 0.064)
        tuning[.machineKickLevel] = TunableRange(1.05)
        tuning[.machineMetalLevel] = TunableRange(-13.75)
        // A drum kit is not in a key, and a seven-second room under a kick
        // is mud however short the send is — so the drums keep their layout
        // whatever the root is, and only their top half reaches the room.
        tuning[.machineFollowsKey] = TunableRange(0)
        tuning[.machineSendHighpass] = TunableRange(1000)

        tuning[.reverbDecay] = TunableRange(2.92)
        tuning[.reverbPreDelay] = TunableRange(0.0296)
        tuning[.reverbDamping] = TunableRange(6870)

        return tuning
    }()

    static let defaults: [TuningKnob: TunableRange] = [
        // REVERIE. The release is the pad: the web rolls 10–90% of 3.2 s.
        .reverieRelease: TunableRange(0.1 * 3.2, 0.9 * 3.2),
        .reverieSlowAttackChance: TunableRange(0.3),
        .reverieSlowAttack: TunableRange(0.04, 0.35),
        .reverieDetune: TunableRange(14),
        .reverieLevel: TunableRange(-12),

        // KALIMBA
        .kalimbaResonance: TunableRange(0.55, 0.94),
        .kalimbaDampening: TunableRange(900, 4500),
        .kalimbaAttackNoise: TunableRange(0.4, 1.8),
        .kalimbaLowpass: TunableRange(1200, 5200),
        .kalimbaLevel: TunableRange(5),

        // RHODES
        .rhodesModulationIndex: TunableRange(3, 11),
        .rhodesModulationDecay: TunableRange(0.1, 0.5),
        .rhodesModulationSustain: TunableRange(0, 0.2),
        .rhodesTremoloDepth: TunableRange(0.15, 0.55),
        .rhodesLevel: TunableRange(0),

        // ACID
        .acidResonance: TunableRange(4, 11),
        .acidAccentResonance: TunableRange(9, 15),
        .acidBaseCutoff: TunableRange(90, 260),
        .acidOctaves: TunableRange(1.6, 3.4),
        .acidSweep: TunableRange(0.09, 0.42),
        .acidLevel: TunableRange(-18),

        // MACHINE
        .machineKickPitchStart: TunableRange(3, 8),
        .machineKickPitchDecay: TunableRange(0.02, 0.09),
        .machineKickLevel: TunableRange(-3),
        .machineSnareBandpass: TunableRange(1200, 3600),
        .machineMetalLevel: TunableRange(-21),
        // The web transposes the drums with everything else, and rolls the
        // reverb send off at 380 Hz.
        .machineFollowsKey: TunableRange(1),
        .machineSendHighpass: TunableRange(380),
        .machineDelayWet: TunableRange(0.12),

        // The room. Decay and damping are the two that are not the web's —
        // see `Reverb` — so they are the two most worth moving.
        .reverbDecay: TunableRange(7),
        .reverbPreDelay: TunableRange(0.02),
        .reverbDamping: TunableRange(4500),
    ]

    // -------------------------------------------------------------- specs --

    public static let specs: [TuningSpec] = [
        TuningSpec(
            knob: .reverieRelease, preset: .reverie, label: "Release",
            detail: "How long each note hangs on. This is what makes it a pad.",
            bounds: 0.05...8, unit: .seconds),
        TuningSpec(
            knob: .reverieSlowAttackChance, preset: .reverie, label: "Slow notes",
            detail: "How often a note swells in instead of arriving.",
            bounds: 0...1, unit: .chance),
        TuningSpec(
            knob: .reverieSlowAttack, preset: .reverie, label: "Slow attack",
            detail: "How long that swell takes when it happens.",
            bounds: 0.005...1.5, unit: .seconds),
        TuningSpec(
            knob: .reverieDetune, preset: .reverie, label: "Detune",
            detail: "How far notes sit off true. Widen for drift, pin for choir.",
            bounds: 0...60, unit: .cents),
        TuningSpec(
            knob: .reverieLevel, preset: .reverie, label: "Level",
            detail: "The preset's own level, before its chain.",
            bounds: -30...6, unit: .decibels),

        TuningSpec(
            knob: .kalimbaResonance, preset: .kalimba, label: "Resonance",
            detail: "How long the tine rings. High is a harp, low is a knock.",
            bounds: 0...0.995, unit: .ratio),
        TuningSpec(
            knob: .kalimbaDampening, preset: .kalimba, label: "Dampening",
            detail: "How bright the pluck arrives. Low is wooden.",
            bounds: 200...12_000, unit: .hertz),
        TuningSpec(
            knob: .kalimbaAttackNoise, preset: .kalimba, label: "Attack noise",
            detail: "Length of the burst that starts it, in wavelengths. The thump.",
            bounds: 0.05...6, unit: .ratio),
        TuningSpec(
            knob: .kalimbaLowpass, preset: .kalimba, label: "Tone",
            detail: "Where the per-note filter starts before it sweeps down.",
            bounds: 200...12_000, unit: .hertz),
        TuningSpec(
            knob: .kalimbaLevel, preset: .kalimba, label: "Level",
            detail: "The preset's own level, before its chain.",
            bounds: -30...12, unit: .decibels),

        TuningSpec(
            knob: .rhodesModulationIndex, preset: .rhodes, label: "Modulation",
            detail: "How far the modulator bends the carrier. Brightness and bell.",
            bounds: 0...30, unit: .ratio),
        TuningSpec(
            knob: .rhodesModulationDecay, preset: .rhodes, label: "Bell decay",
            detail: "How fast the bell leaves and the warm body is left.",
            bounds: 0.01...2, unit: .seconds),
        TuningSpec(
            knob: .rhodesModulationSustain, preset: .rhodes, label: "Bell tail",
            detail: "How much brightness stays for the length of the note.",
            bounds: 0...1, unit: .ratio),
        TuningSpec(
            knob: .rhodesTremoloDepth, preset: .rhodes, label: "Tremolo depth",
            detail: "How far the note swings across the stereo field.",
            bounds: 0...1, unit: .ratio),
        TuningSpec(
            knob: .rhodesLevel, preset: .rhodes, label: "Level",
            detail: "The preset's own level, before its chain.",
            bounds: -30...6, unit: .decibels),

        TuningSpec(
            knob: .acidResonance, preset: .acid, label: "Resonance",
            detail: "The squelch, in decibels of peak. Web Audio reads it as dB.",
            bounds: 0...24, unit: .decibels),
        TuningSpec(
            knob: .acidAccentResonance, preset: .acid, label: "Accent resonance",
            detail: "The same, on loud cells. This is where the spikes come from.",
            bounds: 0...24, unit: .decibels),
        TuningSpec(
            knob: .acidBaseCutoff, preset: .acid, label: "Base cutoff",
            detail: "Where the sweep starts. Low keeps the fundamental readable.",
            bounds: 40...900, unit: .hertz),
        TuningSpec(
            knob: .acidOctaves, preset: .acid, label: "Sweep range",
            detail: "How many octaves the filter opens through.",
            bounds: 0...7, unit: .ratio),
        TuningSpec(
            knob: .acidSweep, preset: .acid, label: "Sweep time",
            detail: "How fast it falls back. Short is a blip, long is a wow.",
            bounds: 0.01...1.5, unit: .seconds),
        TuningSpec(
            knob: .acidLevel, preset: .acid, label: "Level",
            detail: "Deliberately under the other tracks — it is the bass.",
            bounds: -36...0, unit: .decibels),

        TuningSpec(
            knob: .machineKickPitchStart, preset: .machine, label: "Kick pitch start",
            detail: "How far above the note the drum starts. High is a zap.",
            bounds: 1...24, unit: .ratio),
        TuningSpec(
            knob: .machineKickPitchDecay, preset: .machine, label: "Kick pitch fall",
            detail: "How fast it drops to the note. Long is a tom, short is a kick.",
            bounds: 0.005...0.4, unit: .seconds),
        TuningSpec(
            knob: .machineKickLevel, preset: .machine, label: "Kick level",
            detail: "Kicks and toms only.",
            bounds: -30...6, unit: .decibels),
        TuningSpec(
            knob: .machineSnareBandpass, preset: .machine, label: "Snare band",
            detail: "Where the snare's noise sits. Low is a thud, high is a crack.",
            bounds: 300...9000, unit: .hertz),
        TuningSpec(
            knob: .machineMetalLevel, preset: .machine, label: "Metal level",
            detail: "Hats and cymbals only.",
            bounds: -40...0, unit: .decibels),

        TuningSpec(
            knob: .machineFollowsKey, preset: .machine, label: "Follow the key",
            detail:
                "The web transposes drums too, which slides the whole kit "
                + "between columns when the root moves. Off keeps the layout.",
            bounds: 0...1, unit: .flag),
        TuningSpec(
            knob: .machineSendHighpass, preset: .machine, label: "Reverb cut",
            detail: "Only what sits above this reaches the room.",
            bounds: 60...4000, unit: .hertz),
        TuningSpec(
            knob: .machineDelayWet, preset: .machine, label: "Echo",
            detail: "How much of the kit the ping-pong delay repeats.",
            bounds: 0...0.6, unit: .ratio),

        TuningSpec(
            knob: .reverbDecay, preset: nil, label: "Decay",
            detail: "How long the room takes to fall away.",
            bounds: 0.2...20, unit: .seconds),
        TuningSpec(
            knob: .reverbPreDelay, preset: nil, label: "Pre-delay",
            detail: "The gap before the room answers.",
            bounds: 0...0.2, unit: .seconds),
        TuningSpec(
            knob: .reverbDamping, preset: nil, label: "Damping",
            detail: "Where the tail loses its top. High is bright, as the web is.",
            bounds: 500...20_000, unit: .hertz),
    ]

    public static func specs(for preset: SynthPreset?) -> [TuningSpec] {
        specs.filter { $0.preset == preset }
    }

    // --------------------------------------------------------------- text --

    /// The whole tuning as JSON, so it can leave the phone and come back as
    /// numbers somebody can paste into the source.
    public func json() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(self),
            let text = String(data: data, encoding: .utf8)
        else { return "{}" }
        return text
    }

    public static func fromJSON(_ text: String) -> Tuning? {
        guard let data = text.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(Tuning.self, from: data)
    }

    /// Only what was moved, in the order the panel shows it — which is what
    /// is worth reading out loud.
    public func changes(from reference: Tuning = .tuned)
        -> [(spec: TuningSpec, from: TunableRange, to: TunableRange)]
    {
        Self.specs.compactMap { spec in
            let now = self[spec.knob]
            let was = reference[spec.knob]
            return now == was ? nil : (spec, was, now)
        }
    }
}
