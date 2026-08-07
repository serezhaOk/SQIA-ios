// The shape a sample one-shot is played through: a fast linear attack so
// retriggers stay clean, then an exponential fall.
//
// Port of `Audio.trigger` in the web app's src/audio.ts, where the shape is
// Web Audio parameter automation. Written out as a function of time here
// because the renderer applies it per sample rather than handing it to a
// graph.

import Foundation

public struct SampleEnvelope: Sendable, Equatable {
    public static let attack = 0.006
    /// Where the exponential ends. Web Audio cannot ramp to zero, and the
    /// web app picks this floor; keeping it means the tail dies at the same
    /// rate rather than merely sounding similar.
    public static let floor = 0.0008
    /// The source is stopped a moment after the ramp lands.
    public static let tail = 0.05

    public let peak: Double
    /// Length of the fall, measured from the start of the note.
    public let release: Double

    public init(peak: Double, release: Double) {
        self.peak = max(peak, Self.floor)
        self.release = max(release, Self.attack * 2)
    }

    /// How long a hit rings.
    ///
    /// A sample played fast is over sooner, so the tail is tied to the
    /// sounding length rather than being fixed, then scaled per hit so no
    /// two land identically. Never shorter than 80 ms.
    public static func release(bufferDuration: Double, rate: Double, scale: Double) -> Double {
        max(0.08, min(1.5, bufferDuration / rate) * scale)
    }

    public var duration: Double {
        release + Self.tail
    }

    /// Gain at `t` seconds after the note started.
    public func value(at t: Double) -> Double {
        if t <= 0 { return 0 }
        if t < Self.attack { return peak * (t / Self.attack) }
        if t >= release { return Self.floor }
        // Web Audio's exponential ramp runs from the value standing at the
        // previous automation point (the end of the attack) to the target at
        // the ramp's end: v = v0 · (v1/v0)^((t−t0)/(t1−t0)).
        let span = release - Self.attack
        let progress = (t - Self.attack) / span
        return peak * pow(Self.floor / peak, progress)
    }
}
