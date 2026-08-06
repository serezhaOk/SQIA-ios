// The clock has no fixture to compare against — the web's transport is a
// closure over a running AudioContext, not something the generator can
// sample. So these check the behaviour the web code specifies, with the
// numbers derived from src/audio.ts by hand.

import Testing

@testable import SQIACore

@Suite("Step clock")
struct StepClockTests {
    @Test("A step is a sixteenth note")
    func stepDuration() {
        var clock = StepClock(bpm: 120)
        #expect(clock.stepDuration == 0.125)  // 60/120/4
        clock.bpm = 60
        #expect(clock.stepDuration == 0.25)
        clock.bpm = 240
        #expect(clock.stepDuration == 0.0625)
    }

    @Test("Nothing is scheduled before the clock starts")
    func idleUntilStarted() {
        var clock = StepClock()
        #expect(clock.pump(now: 100).isEmpty)
    }

    @Test("The first step lands after the start delay, not immediately")
    func firstStep() {
        var clock = StepClock(bpm: 120)
        clock.start(now: 10)

        // The window reaches to 10.12, so it catches step 0 at 10.08 and
        // nothing else — step 1 is not due until 10.205.
        let first = clock.pump(now: 10)
        #expect(first.count == 1)
        #expect(first.first?.step == 0)
        #expect(first.first?.time == 10.08)

        // Nothing new until the window moves past the next step.
        #expect(clock.pump(now: 10.05).isEmpty)

        let second = clock.pump(now: 10.1)
        #expect(second.count == 1)
        #expect(second.first?.step == 1)
        #expect(abs((second.first?.time ?? 0) - 10.205) < 1e-12)
    }

    @Test("Steps come out in order and wrap at the end of the bar")
    func wrapsAtTheBar() {
        var clock = StepClock(bpm: 120)
        clock.start(now: 0)

        var steps: [Int] = []
        var now = 0.0
        // Two bars at 120bpm is four seconds; step in the same 25 ms the
        // driving timer would use.
        while now < 4.2 {
            steps += clock.pump(now: now).map(\.step)
            now += StepClock.tickInterval
        }

        #expect(steps.count >= 32)
        #expect(Array(steps.prefix(17)) == Array(0..<16) + [0])
        // Strictly ascending times, no repeats, no gaps in the cycle.
        for (i, step) in steps.enumerated() {
            #expect(step == i % 16)
        }
    }

    @Test("Steps are spaced by exactly one step duration")
    func evenSpacing() {
        var clock = StepClock(bpm: 137)
        clock.start(now: 5)

        var times: [Double] = []
        var now = 5.0
        while now < 8 {
            times += clock.pump(now: now).map(\.time)
            now += StepClock.tickInterval
        }

        #expect(times.count > 20)
        for (a, b) in zip(times, times.dropFirst()) {
            #expect(abs((b - a) - clock.stepDuration) < 1e-12)
        }
    }

    @Test("A tempo change moves the next step, not the ones already given out")
    func tempoChangeAppliesForward() {
        var clock = StepClock(bpm: 120)
        clock.start(now: 0)
        let first = clock.pump(now: 0)
        let scheduled = first.map(\.time)

        clock.bpm = 240
        let after = clock.pump(now: 0.1)

        // What was already handed out is untouched.
        #expect(first.map(\.time) == scheduled)
        // And the new spacing is the faster one.
        if after.count >= 2 {
            #expect(abs((after[1].time - after[0].time) - 0.0625) < 1e-12)
        }
    }

    @Test("Stopping ends the stream")
    func stopping() {
        var clock = StepClock()
        clock.start(now: 0)
        #expect(!clock.pump(now: 0).isEmpty)
        clock.stop()
        #expect(clock.pump(now: 1).isEmpty)
    }

    /// After a suspension the clock's next step is minutes in the past. The
    /// window loop would happily emit every step in between, all at times
    /// that have gone, so the engine needs to be told to resync instead.
    @Test("A long gap is reported rather than replayed")
    func survivesSuspension() {
        var clock = StepClock(bpm: 120)
        clock.start(now: 0)
        _ = clock.pump(now: 0)

        let wokeAt = 600.0
        #expect(clock.hasFallenBehind(now: wokeAt))
        #expect(clock.pump(now: wokeAt).count == 64)  // capped, not thousands

        clock.resync(now: wokeAt)
        #expect(!clock.hasFallenBehind(now: wokeAt))
        let ticks = clock.pump(now: wokeAt)
        #expect(ticks.first?.time == wokeAt + StepClock.startDelay)
    }

    @Test("Restarting an already running clock changes nothing")
    func startIsIdempotent() {
        var clock = StepClock()
        clock.start(now: 3)
        let time = clock.nextTime
        clock.start(now: 99)
        #expect(clock.nextTime == time)
    }
}

@Suite("Tempo control")
struct TempoTests {
    @Test("Dragging scrubs at 0.4 BPM per point")
    func scrub() {
        #expect(Tempo.scrub(from: 120, dx: 0) == 120)
        #expect(Tempo.scrub(from: 120, dx: 100) == 160)
        #expect(Tempo.scrub(from: 120, dx: -100) == 80)
        // Rounded, not truncated.
        #expect(Tempo.scrub(from: 120, dx: 4) == 122)  // 121.6
    }

    @Test("A drag cannot leave the usable range")
    func scrubClamps() {
        #expect(Tempo.scrub(from: 120, dx: 10_000) == 240)
        #expect(Tempo.scrub(from: 120, dx: -10_000) == 40)
    }

    @Test("Tapping climbs by ten and wraps at 200")
    func bump() {
        #expect(Tempo.bump(120) == 130)
        #expect(Tempo.bump(190) == 200)
        #expect(Tempo.bump(200) == 60)
        #expect(Tempo.bump(240) == 60)
    }
}
