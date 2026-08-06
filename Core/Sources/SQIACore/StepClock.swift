// The lookahead clock the sequencer runs on.
//
// Audio has to be scheduled ahead of when it sounds, so nothing here plays
// anything: a timer wakes the clock every 25 ms, the clock hands back every
// step that falls inside the next 120 ms, and the engine schedules those at
// their exact times. Late wake-ups cost nothing because the times were
// already decided.
//
// Port of `Transport` in the web app's src/audio.ts. Times are on the audio
// engine's own clock, in seconds — never wall time.

public struct StepClock: Sendable, Equatable {
    /// How far ahead steps are scheduled.
    public static let lookahead = 0.12
    /// How often the driving timer should wake up.
    public static let tickInterval = 0.025
    /// Breathing room between starting and the first step.
    public static let startDelay = 0.08

    public static let steps = NoteGrid.rows

    /// Beats per minute. Changing it takes effect from the next step on, so
    /// a tempo drag is heard immediately without disturbing what is already
    /// scheduled.
    public var bpm: Double

    public private(set) var isRunning = false
    public private(set) var nextStep = 0
    public private(set) var nextTime = 0.0

    public init(bpm: Double = 120) {
        self.bpm = bpm
    }

    /// A step is a sixteenth: sixteen of them per bar of four beats.
    public var stepDuration: Double {
        60 / bpm / 4
    }

    public mutating func start(now: Double) {
        guard !isRunning else { return }
        isRunning = true
        nextStep = 0
        nextTime = now + Self.startDelay
    }

    public mutating func stop() {
        isRunning = false
    }

    /// One step due for scheduling.
    public struct Tick: Sendable, Equatable {
        public let step: Int
        /// When it sounds, on the engine's clock.
        public let time: Double
    }

    /// Every step falling inside the lookahead window, in order.
    ///
    /// `limit` caps how many steps a single call will emit. It matters after
    /// the app has been suspended: the clock's `nextTime` is then far in the
    /// past, and running the loop to convergence would emit thousands of
    /// steps at times that have already gone by. The engine treats hitting
    /// the limit as "the clock fell behind" and resyncs rather than trying
    /// to play a backlog nobody would hear.
    public mutating func pump(now: Double, limit: Int = 64) -> [Tick] {
        guard isRunning else { return [] }
        var ticks: [Tick] = []
        let horizon = now + Self.lookahead
        while nextTime < horizon && ticks.count < limit {
            ticks.append(Tick(step: nextStep, time: nextTime))
            nextTime += stepDuration
            nextStep = (nextStep + 1) % Self.steps
        }
        return ticks
    }

    /// True when the clock has fallen so far behind that catching up step by
    /// step is pointless — after a suspension, say.
    public func hasFallenBehind(now: Double, by seconds: Double = 0.5) -> Bool {
        isRunning && nextTime < now - seconds
    }

    /// Pick the loop back up from `now`, keeping the position in the bar.
    public mutating func resync(now: Double) {
        guard isRunning else { return }
        nextTime = now + Self.startDelay
    }
}

/// How the tempo control behaves.
///
/// The web app puts this inline in its pointer handlers (src/main.ts): drag
/// horizontally to scrub, tap to bump. Both live here so the numbers are
/// testable and the view is left with nothing but the gesture.
public enum Tempo {
    public static let minimum = 40.0
    public static let maximum = 240.0
    /// BPM per point of horizontal drag.
    public static let dragSensitivity = 0.4
    /// Past this, a tap wraps instead of climbing.
    public static let tapWrapAt = 200.0
    public static let tapStep = 10.0
    public static let tapWrapTo = 60.0
    /// Movement under this is a tap, not a drag.
    public static let dragThreshold = 3.0

    /// Where a drag of `dx` points from `start` lands.
    public static func scrub(from start: Double, dx: Double) -> Double {
        clamp((start + dx * dragSensitivity).rounded(.toNearestOrAwayFromZero))
    }

    /// Where a tap takes the tempo next.
    public static func bump(_ bpm: Double) -> Double {
        bpm >= tapWrapAt ? tapWrapTo : bpm + tapStep
    }

    public static func clamp(_ bpm: Double) -> Double {
        min(maximum, max(minimum, bpm))
    }
}
