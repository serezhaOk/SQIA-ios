// One preset's own colouring: filter → overdrive → chorus → delay, with a
// send into the room everyone shares.
//
// It never sits still. Once a bar the cutoff, the echo's feedback and the
// reverb send are all sent somewhere new, over ramps long enough that the
// move is felt rather than heard. Port of `tick` and `retimeEcho` in the
// web app's src/synths.ts.

import Foundation

/// A parameter on its way somewhere, one sample at a time. Tone's `rampTo`
/// is linear, so this is too.
struct Ramp: Sendable {
    private(set) var value: Double
    private var target: Double
    private var step = 0.0
    private var remaining = 0

    init(_ value: Double) {
        self.value = value
        target = value
    }

    mutating func set(_ value: Double) {
        self.value = value
        target = value
        remaining = 0
    }

    mutating func go(to target: Double, seconds: Double, sampleRate: Double) {
        self.target = target
        remaining = max(1, Int(seconds * sampleRate))
        step = (target - value) / Double(remaining)
    }

    mutating func next() -> Double {
        if remaining > 0 {
            value += step
            remaining -= 1
            if remaining == 0 { value = target }
        }
        return value
    }
}

public struct PresetChain: Sendable {
    public let preset: SynthPreset
    private let settings: PresetSettings
    private let sampleRate: Double

    /// One filter per side: sharing a biquad's state between channels would
    /// smear one into the other.
    private var filterLeft: Biquad
    private var filterRight: Biquad
    private var cutoff: Ramp
    private var chorus: Chorus
    private var delay: PingPongDelay
    private var distortion: Distortion?

    private var feedback: Ramp
    private var send: Ramp
    private var wet: Ramp

    /// Which subdivision of the beat the echo is currently on, and what that
    /// came to in seconds.
    private(set) var division = 0
    private(set) var echo = PingPongDelay.defaultDelayTime

    /// A drift waiting for its downbeat: the echo is being ducked across the
    /// gap, and everything else lands when the count reaches zero.
    private var pending: PresetDrift?
    private var pendingFrames = 0

    /// How often the filter's coefficients are recomputed as the cutoff
    /// ramps. Every sample would be pure waste; every 64 is inaudible.
    private static let filterUpdateInterval = 64
    private var sinceFilterUpdate = 0

    public init(preset: SynthPreset, sampleRate: Double) {
        self.preset = preset
        self.sampleRate = sampleRate
        settings = PresetSettings.of(preset)

        let middle = (settings.cutoff.lowerBound + settings.cutoff.upperBound) / 2
        filterLeft = Biquad(lowpass: middle, q: 1.2, sampleRate: sampleRate)
        filterRight = filterLeft
        cutoff = Ramp(middle)

        chorus = Chorus(depth: 0.55, wet: settings.chorus, sampleRate: sampleRate)
        delay = PingPongDelay(wet: settings.delayWet, sampleRate: sampleRate)
        if let drive = settings.drive {
            // Overdrive sits after the filter, before the modulation — the
            // way a 303 runs into a pedal, so the resonance peak is what
            // gets driven.
            distortion = Distortion(amount: drive, wet: 0.5)
        }

        feedback = Ramp(PingPongDelay.defaultFeedback)
        send = Ramp((settings.reverbWet.lowerBound + settings.reverbWet.upperBound) / 2)
        wet = Ramp(settings.delayWet)
    }

    public mutating func clear() {
        filterLeft.reset()
        filterRight.reset()
        chorus.clear()
        delay.clear()
        pending = nil
        pendingFrames = 0
    }

    /// How much of this chain's output goes to the shared room.
    public var reverbSend: Double { send.value }

    // --------------------------------------------------------------- drift --

    /// Take a bar's drift. The event is scheduled `lead` frames early so the
    /// echo can be ducked before it is retuned.
    public mutating func apply(_ drift: PresetDrift) {
        if drift.echo > 0 && drift.lead > 0 {
            // Retuning a delay line that is still ringing resamples whatever
            // is in its buffer, which pitch-warps the echoes — a gargle right
            // at the turn of the loop. Fade them out across the gap so there
            // is nothing left to warp.
            wet.go(to: 0, seconds: Double(drift.lead) / sampleRate, sampleRate: sampleRate)
            pending = drift
            pendingFrames = drift.lead
        } else {
            land(drift)
        }
    }

    private mutating func land(_ drift: PresetDrift) {
        cutoff.go(
            to: drift.cutoff, seconds: drift.cutoffRamp, sampleRate: sampleRate)
        feedback.go(to: drift.feedback, seconds: 0.5, sampleRate: sampleRate)
        send.go(to: drift.reverbSend, seconds: 1, sampleRate: sampleRate)
        // Chorus depth is a plain number, not a ramped parameter: assigning
        // it steps the modulation and clicks. Nudge it instead, within
        // bounds that keep it a chorus.
        chorus.depth = min(0.8, max(0.2, chorus.depth + drift.chorusDepthDelta))

        if drift.echo > 0 {
            division = 0
            echo = drift.echo
            delay.setDelayTime(drift.echo)
            wet.go(to: settings.delayWet, seconds: 0.2, sampleRate: sampleRate)
        }
    }

    // -------------------------------------------------------------- render --

    public mutating func process(
        left: Double,
        right: Double
    ) -> (left: Double, right: Double) {
        if pendingFrames > 0 {
            pendingFrames -= 1
            if pendingFrames == 0, let drift = pending {
                pending = nil
                land(drift)
            }
        }

        let frequency = cutoff.next()
        sinceFilterUpdate += 1
        if sinceFilterUpdate >= Self.filterUpdateInterval {
            sinceFilterUpdate = 0
            filterLeft.setLowpass(frequency: frequency, q: 1.2, sampleRate: sampleRate)
            filterRight.setLowpass(frequency: frequency, q: 1.2, sampleRate: sampleRate)
        }

        var l = filterLeft.process(left)
        var r = filterRight.process(right)

        if let distortion {
            l = distortion.process(l)
            r = distortion.process(r)
        }

        let chorused = chorus.process(left: l, right: r)
        delay.feedback = feedback.next()
        delay.wet = wet.next()
        _ = send.next()
        return delay.process(left: chorused.left, right: chorused.right)
    }
}
