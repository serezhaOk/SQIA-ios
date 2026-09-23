// The mixer's four knobs: that they are silent when down, stable when all
// the way up, and that each one actually does something in between.

import Foundation
import Testing

@testable import SQIACore

private let rate = 48_000.0

private func rms(_ samples: [Double]) -> Double {
    guard !samples.isEmpty else { return 0 }
    return (samples.reduce(0) { $0 + $1 * $1 } / Double(samples.count)).squareRoot()
}

/// A plucked-ish pattern: a decaying tone on every fourth step at 120 bpm,
/// the kind of material the effects spend their lives on.
private func pattern(frames: Int) -> [Double] {
    let step = Int(0.125 * rate)
    return (0..<frames).map { i in
        let local = i % (step * 4)
        let t = Double(local) / rate
        return 0.4 * sin(2 * .pi * 330 * t) * exp(-t * 9)
    }
}

/// Run a signal through, telling the effects where the steps are the way
/// the transport does.
private func run(
    _ settings: EffectSettings, input: [Double], grid: Bool = true
) -> (left: [Double], right: [Double]) {
    var fx = MasterEffects(sampleRate: rate)
    fx.apply(settings)
    let step = Int64(0.125 * rate)
    var left: [Double] = []
    var right: [Double] = []
    left.reserveCapacity(input.count)
    right.reserveCapacity(input.count)
    for (i, x) in input.enumerated() {
        let frame = Int64(i)
        if grid && frame % step == 0 {
            fx.apply(StepGrid(frame: frame, stepSeconds: 0.125))
        }
        let out = fx.process(left: x, right: x, frame: frame)
        left.append(out.left)
        right.append(out.right)
    }
    return (left, right)
}

@Suite("Master effects")
struct MasterEffectsTests {
    @Test("With every knob down, what comes out is what went in")
    func bypass() {
        let input = pattern(frames: Int(rate * 2))
        let out = run(EffectSettings(), input: input)
        #expect(out.left == input)
        #expect(out.right == input)
    }

    @Test("Everything at full stays finite and bounded for half a minute")
    func stableAtFull() {
        let input = pattern(frames: Int(rate * 30))
        let out = run(EffectSettings(reverb: 1, delay: 1, scatter: 1, cloud: 1), input: input)
        let peak = zip(out.left, out.right).reduce(0.0) { max($0, abs($1.0), abs($1.1)) }
        #expect(out.left.allSatisfy { $0.isFinite })
        #expect(out.right.allSatisfy { $0.isFinite })
        // Loud, since nothing here has been through the limiter yet, but a
        // loop running away would be far past this.
        #expect(peak < 4)
    }

    @Test("Each knob changes the sound on its own, and none runs away")
    func eachDoesSomething() {
        let input = pattern(frames: Int(rate * 8))
        let inputLevel = rms(input)
        for effect in MasterEffect.allCases {
            var settings = EffectSettings()
            settings[effect] = 0.6
            let out = run(settings, input: input)
            let difference = rms(zip(out.left, input).map { $0 - $1 })
            #expect(difference > inputLevel * 0.05, "\(effect.name) did nothing")
            #expect(rms(out.left) < inputLevel * 3, "\(effect.name) is too loud")
        }
    }

    @Test("Echoes carry on after the input stops")
    func tails() {
        var input = pattern(frames: Int(rate * 2))
        input += Array(repeating: 0, count: Int(rate))
        for effect in [MasterEffect.reverb, .delay, .cloud] {
            var settings = EffectSettings()
            settings[effect] = 0.5
            let out = run(settings, input: input)
            let tail = Array(out.left[Int(rate * 2.1)..<Int(rate * 2.6)])
            #expect(rms(tail) > 1e-3, "\(effect.name) has no tail")
        }
    }

    @Test("Scatter does nothing until it knows where the steps are")
    func scatterWaitsForGrid() {
        let input = pattern(frames: Int(rate * 2))
        let out = run(EffectSettings(scatter: 1), input: input, grid: false)
        #expect(out.left == input)
    }

    @Test("Scatter repeats what it caught")
    func scatterRepeats() {
        let step = Int(0.125 * rate)
        // One hit, then silence: anything heard in the silence is a repeat.
        var input = [Double](repeating: 0, count: step * 64)
        for i in 0..<step {
            input[i] = 0.4 * sin(2 * .pi * 330 * Double(i) / rate) * exp(-Double(i) / rate * 30)
        }
        // Repeat the hit every bar so the dice have many chances to catch it.
        for bar in 1..<16 {
            for i in 0..<step { input[bar * step * 4 + i] = input[i] }
        }
        let out = run(EffectSettings(scatter: 1), input: input)
        var repeated = 0.0
        for bar in 0..<16 {
            let silence = (bar * 4 + 1) * step..<(bar * 4 + 4) * step
            repeated = max(repeated, rms(Array(out.left[silence])))
        }
        #expect(repeated > 0.01)
    }

    @Test("Turning a knob down lets its tail ring out rather than cutting it")
    func sendNotCut() {
        var fx = MasterEffects(sampleRate: rate)
        fx.apply(EffectSettings(delay: 0.7))
        fx.apply(StepGrid(frame: 0, stepSeconds: 0.125))
        let input = pattern(frames: Int(rate))
        for (i, x) in input.enumerated() { _ = fx.process(left: x, right: x, frame: Int64(i)) }
        fx.apply(EffectSettings())
        var after: [Double] = []
        for i in 0..<Int(rate * 0.5) {
            after.append(fx.process(left: 0, right: 0, frame: Int64(input.count + i)).left)
        }
        #expect(rms(after) > 1e-3)
    }
}
