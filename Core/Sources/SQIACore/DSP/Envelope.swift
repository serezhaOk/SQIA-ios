// Envelopes: the shape of a note's loudness, and of a drum's pitch.
//
// Tone.js attacks linearly and decays and releases exponentially, so these
// do the same. A note is triggered for a set duration and releases itself —
// which is what `triggerAttackRelease` means and what every preset uses.

import Foundation

/// Attack, decay, sustain, release, sampled one frame at a time.
public struct ADSR: Sendable {
    /// Where an exponential segment is considered finished. Tone ramps
    /// toward a floor rather than to zero, because zero has no logarithm.
    public static let floor = 0.001

    public var attack: Double
    public var decay: Double
    public var sustain: Double
    public var release: Double

    private enum Stage {
        case idle
        case attack
        case decay
        case sustain
        case release
    }

    private var stage: Stage = .idle
    private var time = 0.0
    /// Level the release started from, so a note cut during its attack
    /// falls from where it actually was.
    private var releaseFrom = 0.0
    private var value = 0.0
    /// How long the note is held before it releases itself.
    private var holdFor = 0.0

    public init(
        attack: Double = 0.005,
        decay: Double = 0.1,
        sustain: Double = 0.5,
        release: Double = 0.3
    ) {
        self.attack = max(0, attack)
        self.decay = max(1e-4, decay)
        self.sustain = min(max(sustain, 0), 1)
        self.release = max(1e-4, release)
    }

    public var isFinished: Bool {
        stage == .idle
    }

    /// Total length of a note held for `duration`, which is what the voice
    /// pool uses to know when the slot comes free.
    public func lifetime(duration: Double) -> Double {
        max(duration, attack) + release
    }

    public mutating func trigger(duration: Double) {
        stage = .attack
        time = 0
        value = 0
        holdFor = max(0, duration)
    }

    public mutating func releaseNow() {
        guard stage != .idle, stage != .release else { return }
        releaseFrom = value
        stage = .release
        time = 0
    }

    /// The envelope's level for this frame.
    public mutating func next(sampleRate: Double) -> Double {
        let step = 1 / sampleRate

        switch stage {
        case .idle:
            value = 0

        case .attack:
            value = attack <= 0 ? 1 : min(1, time / attack)
            time += step
            if time >= attack {
                stage = .decay
                time = 0
            }

        case .decay:
            // Toward the sustain level, approaching it rather than sliding.
            let x = min(1, time / decay)
            value = sustain + (1 - sustain) * pow(Self.floor, x)
            time += step
            if time >= decay {
                stage = .sustain
                time = 0
                value = sustain
            }

        case .sustain:
            value = sustain
            time += step

        case .release:
            let x = min(1, time / release)
            value = releaseFrom * pow(Self.floor, x)
            time += step
            if time >= release {
                stage = .idle
                value = 0
            }
        }

        // The note lets go of itself once it has been held long enough.
        if stage != .release && stage != .idle && elapsed >= holdFor {
            releaseNow()
        }
        return value
    }

    /// Time since the attack began.
    private var elapsed: Double {
        switch stage {
        case .idle, .release: return .infinity
        case .attack: return time
        case .decay: return attack + time
        case .sustain: return attack + decay + time
        }
    }
}

/// A drum's pitch drop: start high, fall to the note over `decay`.
///
/// This is what a membrane synth is — a sine whose frequency collapses,
/// which the ear hears as a skin being struck.
public struct PitchEnvelope: Sendable {
    public var octaves: Double
    public var decay: Double

    private var time = 0.0

    public init(octaves: Double, decay: Double) {
        self.octaves = octaves
        self.decay = max(1e-4, decay)
    }

    public mutating func reset() {
        time = 0
    }

    public mutating func next(base frequency: Double, sampleRate: Double) -> Double {
        let x = min(1, time / decay)
        time += 1 / sampleRate
        // Exponential in pitch, which is linear in octaves.
        return frequency * pow(2, octaves * pow(ADSR.floor, x))
    }
}
