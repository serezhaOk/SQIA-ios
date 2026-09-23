// The four knobs on the mixer: Reverb, Delay, Scatter and Cloud, over the
// whole mix.
//
// They sit after everything the presets do — their own chains, the shared
// room — and before the limiter. Scatter goes first, because it cuts the
// sound itself; the other three are sends that listen to what it leaves,
// and the reverb also hears the two echoes, so their repeats land in the
// same space as the notes they repeat.
//
// Each is one knob, 0…1, that opens several things at once. At zero every
// one of them is a true bypass: what comes out is exactly what went in.

import Foundation

public enum MasterEffect: Int, CaseIterable, Sendable {
    case reverb
    case delay
    case scatter
    case cloud

    public var name: String {
        switch self {
        case .reverb: "Reverb"
        case .delay: "Delay"
        case .scatter: "Scatter"
        case .cloud: "Cloud"
        }
    }
}

/// Where the four knobs are, 0…1 each.
public struct EffectSettings: Sendable, Equatable, Codable {
    public var reverb: Double
    public var delay: Double
    public var scatter: Double
    public var cloud: Double

    public init(reverb: Double = 0, delay: Double = 0, scatter: Double = 0, cloud: Double = 0) {
        self.reverb = reverb
        self.delay = delay
        self.scatter = scatter
        self.cloud = cloud
    }

    public subscript(effect: MasterEffect) -> Double {
        get {
            switch effect {
            case .reverb: reverb
            case .delay: delay
            case .scatter: scatter
            case .cloud: cloud
            }
        }
        set {
            let v = min(max(newValue, 0), 1)
            switch effect {
            case .reverb: reverb = v
            case .delay: delay = v
            case .scatter: scatter = v
            case .cloud: cloud = v
            }
        }
    }

    public var isBypassed: Bool { reverb == 0 && delay == 0 && scatter == 0 && cloud == 0 }
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
    /// The room's ring, in seconds, from the knob's first notch to its last.
    public static let shortestRoom = 1.4
    public static let longestRoom = 6.0

    private var scatter: Scatter
    private var echo: TapeEcho
    private var cloud: CloudDelay
    private var room: Reverb
    private var roomSend: Glide
    private var roomCutLeft: SmoothingHighpass
    private var roomCutRight: SmoothingHighpass
    private var roomAmount = -1.0
    private let sampleRate: Double

    /// Samples each send has been silent for. Past a second the effect is
    /// not computed at all, which is what keeps three idle knobs free.
    private var echoQuiet = 0
    private var cloudQuiet = 0
    private var roomQuiet = 0
    private let restAfter: Int

    public init(sampleRate: Double) {
        self.sampleRate = sampleRate
        scatter = Scatter(sampleRate: sampleRate)
        echo = TapeEcho(sampleRate: sampleRate)
        cloud = CloudDelay(sampleRate: sampleRate)
        room = Reverb(
            decay: Self.shortestRoom, preDelay: 0.025, damping: 6_000, sampleRate: sampleRate)
        roomSend = Glide(0, seconds: 0.03, sampleRate: sampleRate)
        roomCutLeft = SmoothingHighpass(frequency: 180, sampleRate: sampleRate)
        roomCutRight = SmoothingHighpass(frequency: 180, sampleRate: sampleRate)
        restAfter = Int(sampleRate)
        echoQuiet = restAfter
        cloudQuiet = restAfter
        roomQuiet = restAfter
    }

    public mutating func apply(_ settings: EffectSettings) {
        scatter.setAmount(settings.scatter)
        echo.setAmount(settings.delay)
        cloud.setAmount(settings.cloud)

        let a = min(max(settings.reverb, 0), 1)
        // A four-line room gets loud as it gets long, so the send backs off
        // a little as the tail grows.
        roomSend.target = knobCurve(a) * (0.9 - 0.25 * a)
        if a != roomAmount {
            roomAmount = a
            room.retune(
                decay: Self.shortestRoom + (Self.longestRoom - Self.shortestRoom) * a,
                preDelay: 0.025, damping: 6_000 - 2_000 * a)
        }
    }

    public mutating func apply(_ grid: StepGrid) {
        scatter.setGrid(frame: grid.frame, stepSeconds: grid.stepSeconds)
        echo.setStep(seconds: grid.stepSeconds)
        cloud.setStep(seconds: grid.stepSeconds)
    }

    public mutating func clear() {
        scatter.clear()
        echo.clear()
        cloud.clear()
        room.clear()
        roomCutLeft.reset()
        roomCutRight.reset()
        echoQuiet = restAfter
        cloudQuiet = restAfter
        roomQuiet = restAfter
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
        var toRoomLeft = dry.left
        var toRoomRight = dry.right

        if echo.isSending || echoQuiet < restAfter {
            let e = echo.process(left: dry.left, right: dry.right)
            outLeft += e.left
            outRight += e.right
            toRoomLeft += e.left
            toRoomRight += e.right
            echoQuiet = Self.silent(e) ? echoQuiet + 1 : 0
        }

        if cloud.isSending || cloudQuiet < restAfter {
            let c = cloud.process(left: dry.left, right: dry.right)
            outLeft += c.left
            outRight += c.right
            toRoomLeft += c.left
            toRoomRight += c.right
            cloudQuiet = Self.silent(c) ? cloudQuiet + 1 : 0
        }

        let send = roomSend.next()
        if send != 0 || roomQuiet < restAfter {
            let r = room.process(
                left: roomCutLeft.process(toRoomLeft) * send,
                right: roomCutRight.process(toRoomRight) * send)
            outLeft += r.left
            outRight += r.right
            roomQuiet = send == 0 && Self.silent(r) ? roomQuiet + 1 : 0
        }

        return (outLeft, outRight)
    }

    private static func silent(_ x: (left: Double, right: Double)) -> Bool {
        abs(x.left) + abs(x.right) < 1e-7
    }
}
