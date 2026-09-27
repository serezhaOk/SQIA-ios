// The two knobs on the mixer: Delay and Scatter, over the whole mix.
//
// They sit after everything the presets do — their own chains, the shared
// room — and before the limiter. Scatter goes first, because it cuts the
// sound itself; the delay is a send that listens to what it leaves.
//
// There used to be four; Reverb and Cloud came off the mixer at the
// owner's call. The shared room every preset stands in is not this and is
// untouched — it lives in the mixer.
//
// Each is one knob, 0…1, that opens several things at once. At zero each
// is a true bypass: what comes out is exactly what went in.

import Foundation

public enum MasterEffect: Int, CaseIterable, Sendable {
    case delay
    case scatter

    public var name: String {
        switch self {
        case .delay: "Delay"
        case .scatter: "Scatter"
        }
    }
}

/// Where the two knobs are, 0…1 each.
///
/// A setting saved while there were four still decodes: the synthesised
/// decoder skips the `reverb` and `cloud` keys it no longer has.
public struct EffectSettings: Sendable, Equatable, Codable {
    public var delay: Double
    public var scatter: Double

    public init(delay: Double = 0, scatter: Double = 0) {
        self.delay = delay
        self.scatter = scatter
    }

    public subscript(effect: MasterEffect) -> Double {
        get {
            switch effect {
            case .delay: delay
            case .scatter: scatter
            }
        }
        set {
            let v = min(max(newValue, 0), 1)
            switch effect {
            case .delay: delay = v
            case .scatter: scatter = v
            }
        }
    }

    public var isBypassed: Bool { delay == 0 && scatter == 0 }
}

/// Where the transport's steps fall, so the effects can keep time with it.
public struct StepGrid: Sendable, Equatable {
    /// A frame a step lands on.
    public var frame: Int64
    public var stepSeconds: Double

    public init(frame: Int64 = 0, stepSeconds: Double = 0.125) {
        self.frame = frame
        self.stepSeconds = stepSeconds
    }
}

public struct MasterEffects: Sendable {
    private var scatter: Scatter
    private var echo: TapeEcho

    /// Samples the echo has been silent for. Past a second it is not
    /// computed at all, which is what keeps an idle knob free.
    private var echoQuiet = 0
    private let restAfter: Int

    public init(sampleRate: Double) {
        scatter = Scatter(sampleRate: sampleRate)
        echo = TapeEcho(sampleRate: sampleRate)
        restAfter = Int(sampleRate)
        echoQuiet = restAfter
    }

    public mutating func apply(_ settings: EffectSettings) {
        scatter.setAmount(settings.scatter)
        echo.setAmount(settings.delay)
    }

    public mutating func apply(_ grid: StepGrid) {
        scatter.setGrid(frame: grid.frame, stepSeconds: grid.stepSeconds)
        echo.setStep(seconds: grid.stepSeconds)
    }

    public mutating func clear() {
        scatter.clear()
        echo.clear()
        echoQuiet = restAfter
    }

    public mutating func process(left: Double, right: Double, frame: Int64)
        -> (left: Double, right: Double)
    {
        var dry = (left: left, right: right)
        if scatter.isActive {
            dry = scatter.process(left: left, right: right, frame: frame)
        }

        var outLeft = dry.left
        var outRight = dry.right

        if echo.isSending || echoQuiet < restAfter {
            let e = echo.process(left: dry.left, right: dry.right)
            outLeft += e.left
            outRight += e.right
            echoQuiet = Self.silent(e) ? echoQuiet + 1 : 0
        }

        return (outLeft, outRight)
    }

    private static func silent(_ x: (left: Double, right: Double)) -> Bool {
        abs(x.left) + abs(x.right) < 1e-7
    }
}
