// The five voices, and what one note of any of them looks like.
//
// Every preset follows the same rule: random within a frame. Pitches always
// come from the grid's scale, but the timbre is re-rolled on every note and
// the patch drifts once a bar, so a pattern never repeats itself exactly.
//
// Port of src/synths.ts. A note is rolled on the transport thread into a
// recipe — a flat description with no references and nothing left to decide
// — and the renderer builds a voice from it without allocating.

import Foundation

public enum SynthPreset: Int, Sendable, CaseIterable {
    case reverie
    case kalimba
    case rhodes
    case acid
    case machine

    public var label: String {
        switch self {
        case .reverie: return "REVERIE"
        case .kalimba: return "KALIMBA"
        case .rhodes: return "RHODES"
        case .acid: return "ACID"
        case .machine: return "MACHINE"
        }
    }

    public var hint: String {
        switch self {
        case .reverie: return "Drifting pad, long random tails"
        case .kalimba: return "Muted wooden pluck"
        case .rhodes: return "Electric piano, shimmering"
        case .acid: return "Squelching 303 bass"
        case .machine: return "Synthesised drums"
        }
    }

    /// The presets that have voices behind them. The rest are being written;
    /// the picker offers what can actually be heard.
    public static let available: [SynthPreset] = [.reverie, .machine]
}

/// Where a preset's shared chain sits, and how far it is allowed to wander.
public struct PresetSettings: Sendable {
    public var cutoff: ClosedRange<Double>
    public var chorus: Double
    public var delayWet: Double
    public var reverbWet: ClosedRange<Double>
    /// Overdrive in the chain, nil for none. The 303 wants some.
    public var drive: Double?

    public static let table: [SynthPreset: PresetSettings] = [
        .reverie: PresetSettings(
            cutoff: 500...5200, chorus: 0.5, delayWet: 0.28, reverbWet: 0.25...0.55,
            drive: nil),
        .kalimba: PresetSettings(
            cutoff: 700...3400, chorus: 0.25, delayWet: 0.2, reverbWet: 0.2...0.4,
            drive: nil),
        .rhodes: PresetSettings(
            cutoff: 900...6000, chorus: 0.6, delayWet: 0.18, reverbWet: 0.2...0.42,
            drive: nil),
        // The chain filter stays out of the way — on acid the sweep belongs
        // to the per-note filter, and the reverb stays dry so the bass keeps
        // its edge.
        .acid: PresetSettings(
            cutoff: 6000...12000, chorus: 0, delayWet: 0.22, reverbWet: 0.04...0.16,
            drive: 0.08),
        .machine: PresetSettings(
            cutoff: 1200...9000, chorus: 0.1, delayWet: 0.12, reverbWet: 0.06...0.22,
            drive: nil),
    ]

    public static func of(_ preset: SynthPreset) -> PresetSettings {
        table[preset] ?? table[.reverie]!
    }
}

/// What a voice is made of. Flat and copyable on purpose: it crosses from
/// the transport thread to the renderer through a lock-free queue.
public struct VoiceRecipe: Sendable, Equatable {
    public enum Source: Int, Sendable {
        case oscillator
        case noise
        /// Six inharmonic partials — a cymbal.
        case metal
    }

    public enum Filter: Int, Sendable {
        case none
        case lowpass
        case bandpass
        case highpass
    }

    public var preset: SynthPreset = .reverie
    public var source: Source = .oscillator

    public var frequency: Double = 440
    /// How long the note is held before it releases itself.
    public var duration: Double = 0.2
    /// Linear, already carrying the preset's level and the note's velocity.
    public var gain: Double = 1

    public var waveform: Waveform = .sine
    public var detuneCents: Double = 0
    public var noiseColour: NoiseColour = .white

    public var attack: Double = 0.005
    public var decay: Double = 0.1
    public var sustain: Double = 0.5
    public var release: Double = 0.3

    /// Octaves the pitch falls through at the start; zero for no drop.
    public var pitchOctaves: Double = 0
    public var pitchDecay: Double = 0.05

    public var filter: Filter = .none
    public var filterFrequency: Double = 20_000
    public var filterQ: Double = 1

    // Metal only.
    public var harmonicity: Double = 5
    public var modulationIndex: Double = 20
    public var resonance: Double = 4000

    public init() {}

    /// A level in decibels, as Tone states them, as a linear gain.
    public static func gain(db: Double, velocity: Double = 1) -> Double {
        pow(10, db / 20) * velocity
    }
}

/// One bar's worth of drift for a preset's chain.
///
/// Rolled on the transport thread and scheduled a little before the
/// downbeat, because retuning a delay that is still ringing has to be
/// covered — see `PresetChain`.
public struct PresetDrift: Sendable, Equatable {
    public var preset: SynthPreset = .reverie
    public var cutoff: Double = 2000
    public var cutoffRamp: Double = 1
    public var feedback: Double = 0.38
    public var reverbSend: Double = 0.3
    /// How far to nudge the chorus depth, not where to put it — the web
    /// reads the current value and adds to it.
    public var chorusDepthDelta: Double = 0
    /// The new echo spacing, or zero to leave it where it is.
    public var echo: Double = 0
    /// Frames between the event landing and the downbeat it belongs to.
    public var lead: Int = 0

    public init() {}
}
