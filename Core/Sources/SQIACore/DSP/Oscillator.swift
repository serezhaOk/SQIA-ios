// The waveforms the presets draw from.
//
// The web rolls a fresh oscillator type on every REVERIE note out of eight
// Tone.js shapes, so all eight are here — and in the same order, because the
// roll is an index into that list and a seeded comparison depends on it.
//
// Sawtooth and square are band-limited with PolyBLEP. A browser's oscillator
// is band-limited too, and the naive shapes would arrive with an aliasing
// buzz that has nothing to do with the sound being ported.

import Foundation

public enum Waveform: Int, Sendable, CaseIterable {
    case sine
    case triangle
    case fatSawtooth
    case fatTriangle
    case fmSine
    case fmTriangle
    case amSine
    case square
    /// One plain blade. REVERIE only ever asks for the fat sawtooth; the
    /// 303 wants a single one, so it comes last and disturbs no raw value
    /// above it.
    case sawtooth

    /// The order the web's OSC_TYPES lists them in.
    public static let reverieChoices: [Waveform] = [
        .sine, .triangle, .fatSawtooth, .fatTriangle, .fmSine, .fmTriangle, .amSine,
        .square,
    ]
}

public struct Oscillator: Sendable {
    /// Tone's fat oscillators default to three voices spread over 20 cents.
    public static let fatVoices = 3
    public static let fatSpreadCents = 20.0
    /// The outer voices' frequency ratios. Constants, worked out once —
    /// they were being raised to a power on every sample of every note.
    private static let fatLow = pow(2, -fatSpreadCents / 2 / 1200)
    private static let fatHigh = pow(2, fatSpreadCents / 2 / 1200)
    /// Tone's FM and AM oscillators default to these.
    public static let modulationIndex = 2.0
    public static let harmonicity = 1.0

    public var waveform: Waveform

    /// Carrier, and two more for a fat stack. The modulator borrows the
    /// second when the shape needs one.
    private var phase = 0.0
    private var phaseB = 0.0
    private var phaseC = 0.0

    public init(waveform: Waveform = .sine, phase: Double = 0) {
        self.waveform = waveform
        self.phase = phase
    }

    public mutating func reset() {
        phase = 0
        phaseB = 0
        phaseC = 0
    }

    // ------------------------------------------------------------- shapes --

    /// Correction that rounds off a discontinuity, so a step does not fold
    /// the whole spectrum back on itself.
    private static func polyBLEP(_ t: Double, _ dt: Double) -> Double {
        if dt <= 0 { return 0 }
        if t < dt {
            let x = t / dt
            return x + x - x * x - 1
        }
        if t > 1 - dt {
            let x = (t - 1) / dt
            return x * x + x + x + 1
        }
        return 0
    }

    private static func sine(_ t: Double) -> Double {
        sin(2 * .pi * t)
    }

    /// Starts at zero and rises, the way a sine does, so mixing the two does
    /// not fight.
    private static func triangle(_ t: Double) -> Double {
        if t < 0.25 { return 4 * t }
        if t < 0.75 { return 2 - 4 * t }
        return 4 * t - 4
    }

    private static func sawtooth(_ t: Double, _ dt: Double) -> Double {
        2 * t - 1 - polyBLEP(t, dt)
    }

    private static func square(_ t: Double, _ dt: Double) -> Double {
        let raw = t < 0.5 ? 1.0 : -1.0
        let half = (t + 0.5).truncatingRemainder(dividingBy: 1)
        return raw + polyBLEP(t, dt) - polyBLEP(half, dt)
    }

    /// Wraps in either direction: frequency modulation can drive the
    /// instantaneous frequency below zero, and when it does the phase runs
    /// backwards. That is not an error to be clamped away — it is part of
    /// what FM sounds like.
    private static func advance(_ phase: inout Double, by increment: Double) {
        phase += increment
        phase -= phase.rounded(.down)
    }

    // -------------------------------------------------------------- render --

    /// One sample at an instantaneous frequency that is allowed to be
    /// negative.
    ///
    /// Frequency modulation of any depth drives the carrier below zero on
    /// half of every modulator cycle, and when it does the phase is supposed
    /// to run backwards. Holding it at zero instead leaves the carrier
    /// creeping forward a little every cycle, which is a patch that drifts
    /// sharp. Only the simple shapes are offered, because a modulated
    /// band-limited sawtooth has no meaningful `dt` to correct with.
    public mutating func renderSigned(frequency: Double, sampleRate: Double) -> Double {
        let nyquist = sampleRate / 2
        let f = min(max(frequency, -nyquist), nyquist)
        let value: Double
        switch waveform {
        case .triangle, .fatTriangle, .fmTriangle:
            value = Self.triangle(phase)
        default:
            value = Self.sine(phase)
        }
        Self.advance(&phase, by: f / sampleRate)
        return value
    }

    /// One sample at `frequency`, which may move from call to call — a drum's
    /// pitch envelope does exactly that.
    public mutating func render(frequency: Double, sampleRate: Double) -> Double {
        let f = max(0, min(frequency, sampleRate / 2))
        let dt = f / sampleRate

        switch waveform {
        case .sine:
            let value = Self.sine(phase)
            Self.advance(&phase, by: dt)
            return value

        case .triangle:
            let value = Self.triangle(phase)
            Self.advance(&phase, by: dt)
            return value

        case .square:
            let value = Self.square(phase, dt)
            Self.advance(&phase, by: dt)
            return value

        case .sawtooth:
            let value = Self.sawtooth(phase, dt)
            Self.advance(&phase, by: dt)
            return value

        case .fatSawtooth, .fatTriangle:
            // Three voices spread across the detune range, summed and
            // levelled — the thickness comes from them drifting apart.
            let dtA = dt * Self.fatLow
            let dtC = dt * Self.fatHigh

            let value: Double
            if waveform == .fatSawtooth {
                value =
                    Self.sawtooth(phase, dtA) + Self.sawtooth(phaseB, dt)
                    + Self.sawtooth(phaseC, dtC)
            } else {
                value = Self.triangle(phase) + Self.triangle(phaseB) + Self.triangle(phaseC)
            }
            Self.advance(&phase, by: dtA)
            Self.advance(&phaseB, by: dt)
            Self.advance(&phaseC, by: dtC)
            return value / Double(Self.fatVoices)

        case .fmSine, .fmTriangle:
            // The modulator bends the carrier's frequency; the depth is the
            // modulation index times the modulator's own frequency.
            let modulator = Self.sine(phaseB)
            let deviation = Self.modulationIndex * f * Self.harmonicity * modulator
            // Symmetric limits: holding the low side at zero while the high
            // side swings free would leave the carrier drifting forward a
            // little on every cycle.
            let nyquist = sampleRate / 2
            let carrierStep = min(max(f + deviation, -nyquist), nyquist) / sampleRate
            let value =
                waveform == .fmSine ? Self.sine(phase) : Self.triangle(phase)
            Self.advance(&phase, by: carrierStep)
            Self.advance(&phaseB, by: dt * Self.harmonicity)
            return value

        case .amSine:
            // The modulator opens and closes the carrier between silence and
            // full, rather than inverting it.
            let modulator = (Self.sine(phaseB) + 1) / 2
            let value = Self.sine(phase) * modulator
            Self.advance(&phase, by: dt)
            Self.advance(&phaseB, by: dt * Self.harmonicity)
            return value
        }
    }
}
