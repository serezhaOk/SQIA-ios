// Envelopes: the shape of a note's loudness, and of a drum's pitch.
//
// Tone.js attacks linearly and decays and releases exponentially, so these
// do the same. A note is triggered for a set duration and releases itself —
// which is what `triggerAttackRelease` means and what every preset uses.
//
// The curves are stepped rather than evaluated: an exponential segment is a
// constant multiply per sample, a linear one a constant add. Calling `pow`
// once per sample per voice is what a render thread cannot afford, and the
// shape is identical either way.

import Foundation

/// Attack, decay, sustain, release, sampled one frame at a time.
public struct ADSR: Sendable {
    /// Where an exponential segment is considered finished. Tone ramps
    /// toward a floor rather than to zero, because zero has no logarithm.
    public static let floor = 0.001

    public private(set) var attack: Double
    public private(set) var decay: Double
    public private(set) var sustain: Double
    public private(set) var release: Double

    private enum Stage {
        case idle
        case attack
        case decay
        case sustain
        case release
    }

    private var stage: Stage = .idle
    private var value = 0.0

    // Per-sample steps, worked out once when the note starts.
    private var attackStep = 1.0
    private var decayFactor = 0.0
    private var releaseFactor = 0.0
    /// The falling part of the decay, from one down toward zero.
    private var decayLevel = 1.0

    private var age = 0
    private var holdFrames = 0
    private var attackFrames = 0
    private var decayFrames = 0
    private var releaseFrames = 0
    private var releaseAge = 0

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

    public mutating func trigger(duration: Double, sampleRate: Double) {
        stage = .attack
        value = 0
        decayLevel = 1
        age = 0
        releaseAge = 0

        attackFrames = max(0, Int(attack * sampleRate))
        decayFrames = max(1, Int(decay * sampleRate))
        releaseFrames = max(1, Int(release * sampleRate))
        holdFrames = max(0, Int(max(0, duration) * sampleRate))

        attackStep = attackFrames > 0 ? 1 / Double(attackFrames) : 1
        decayFactor = pow(Self.floor, 1 / Double(decayFrames))
        releaseFactor = pow(Self.floor, 1 / Double(releaseFrames))
    }

    public mutating func releaseNow() {
        guard stage != .idle, stage != .release else { return }
        stage = .release
        releaseAge = 0
    }

    /// The envelope's level for this frame.
    public mutating func next() -> Double {
        switch stage {
        case .idle:
            return 0

        case .attack:
            value = attackFrames > 0 ? min(1, value + attackStep) : 1
            age += 1
            if age >= attackFrames {
                stage = .decay
                decayLevel = 1
            }

        case .decay:
            decayLevel *= decayFactor
            value = sustain + (1 - sustain) * decayLevel
            age += 1
            if age >= attackFrames + decayFrames {
                stage = .sustain
                value = sustain
            }

        case .sustain:
            value = sustain
            age += 1

        case .release:
            value *= releaseFactor
            releaseAge += 1
            if releaseAge >= releaseFrames {
                stage = .idle
                value = 0
            }
        }

        // The note lets go of itself once it has been held long enough.
        if stage != .release && stage != .idle && age >= holdFrames {
            releaseNow()
        }
        return value
    }
}

/// A drum's pitch drop: start high, fall to the note over `decay`.
///
/// This is what a membrane synth is — a sine whose frequency collapses,
/// which the ear hears as a skin being struck. Tone ramps it exponentially,
/// which is a constant ratio per sample, so that is how it is stepped.
public struct PitchEnvelope: Sendable {
    public private(set) var octaves: Double
    public private(set) var decay: Double

    private var multiplier = 1.0
    private var perSample = 1.0

    public init(octaves: Double, decay: Double) {
        self.octaves = octaves
        self.decay = max(1e-4, decay)
    }

    public mutating func prepare(sampleRate: Double) {
        multiplier = pow(2, octaves)
        let frames = max(1, Int(decay * sampleRate))
        perSample = pow(2, -octaves / Double(frames))
    }

    public mutating func reset() {
        multiplier = pow(2, octaves)
    }

    public mutating func next(base frequency: Double) -> Double {
        let value = frequency * multiplier
        multiplier = max(1, multiplier * perSample)
        return value
    }
}
