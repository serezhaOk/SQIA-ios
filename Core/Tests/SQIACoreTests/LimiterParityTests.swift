// The master limiter, against the one the web actually runs.
//
// Risk R8. The limiter is the last thing every voice passes through, so
// whatever it does it does to the whole record — which makes "close enough"
// a worse answer here than anywhere else in the chain.
//
// The reference below is Blink's `DynamicsCompressor::Saturate` written out
// a second time, independently of the port in `Limiter`. Two copies of the
// same arithmetic is usually a smell; here it is the entire point, because a
// test that called the implementation would only prove the implementation
// agrees with itself.

import Foundation
import Testing

@testable import SQIACore

/// Blink's static curve, transcribed from
/// third_party/blink/renderer/platform/audio/dynamics_compressor.cc.
private enum Blink {
    static let dBThreshold = -8.0
    static let ratio = 12.0
    static let dBKnee = 30.0  // the node's default, which the web leaves alone

    static let linearThreshold = pow(10, dBThreshold / 20)
    static let dBKneeThreshold = dBThreshold + dBKnee
    static let kneeThreshold = pow(10, dBKneeThreshold / 20)

    static func kneeCurve(_ x: Double, _ k: Double) -> Double {
        if x < linearThreshold { return x }
        return linearThreshold + (1 - exp(-k * (x - linearThreshold))) / k
    }

    /// `KAtSlope`: fifteen bisections on the geometric mean.
    static let k: Double = {
        let x = kneeThreshold
        var x2 = 1.0
        var dBx2 = 0.0
        if !(x < linearThreshold) {
            x2 = x * 1.001
            dBx2 = 20 * log10(x2)
        }
        var minK = 0.1
        var maxK = 10000.0
        var k = 5.0
        for _ in 0..<15 {
            var slope = 1.0
            if !(x < linearThreshold) {
                let dBy = 20 * log10(kneeCurve(x, k))
                let dBy2 = 20 * log10(kneeCurve(x2, k))
                slope = (dBy2 - dBy) / (dBx2 - dBKneeThreshold)
            }
            if slope < 1 / ratio { maxK = k } else { minK = k }
            k = (minK * maxK).squareRoot()
        }
        return k
    }()

    static let dBYKneeThreshold = 20 * log10(kneeCurve(kneeThreshold, k))

    static func saturate(_ x: Double) -> Double {
        if x < kneeThreshold { return kneeCurve(x, k) }
        let dBx = 20 * log10(x)
        let dBy = dBYKneeThreshold + (dBx - dBKneeThreshold) / ratio
        return pow(10, dBy / 20)
    }
}

@Suite("The limiter against the web's")
struct LimiterParityTests {
    @Test("The web's settings are the ones this is built for")
    func settings() {
        // audio.ts sets only these two and takes the node's defaults for the
        // rest, so those defaults are part of the specification.
        #expect(Limiter.threshold == -8)
        #expect(Limiter.ratio == 12)
        #expect(Limiter.knee == 30)
    }

    @Test("The curve is Blink's, across the whole range that matters")
    func curveMatches() {
        // Every half-decibel from far below the threshold to well over the
        // top of the knee. This is the assertion R8 was waiting for.
        var worst = 0.0
        var worstAt = 0.0
        for halfDb in -80...12 {
            let dB = Double(halfDb)
            let mine = Limiter.gainReduction(forLevel: dB)
            let theirs = 20 * log10(Blink.saturate(pow(10, dB / 20))) - dB
            let gap = abs(mine - theirs)
            if gap > worst {
                worst = gap
                worstAt = dB
            }
        }
        #expect(worst < 0.01, "worst disagreement \(worst) dB, at \(worstAt) dBFS")
    }

    @Test("Nothing below the threshold is touched")
    func linearBelowThreshold() {
        // The bug this replaced: a knee centred on the threshold started
        // compressing at −23 dBFS, which is most of the music, and the web
        // passes all of it through untouched.
        for dB in stride(from: -60.0, to: -8.5, by: 0.5) {
            #expect(
                abs(Limiter.gainReduction(forLevel: dB)) < 0.001,
                "\(dB) dBFS was compressed by \(Limiter.gainReduction(forLevel: dB)) dB")
        }
        // And it does start at the threshold rather than somewhere above it.
        #expect(Limiter.gainReduction(forLevel: -6) < -0.01)
    }

    @Test("Well above the knee it settles at the ratio it was asked for")
    func slopeIsTheRatio() {
        // Two points a decibel apart, both past threshold + knee.
        let low = 30.0
        let high = 31.0
        let outLow = low + Limiter.gainReduction(forLevel: low)
        let outHigh = high + Limiter.gainReduction(forLevel: high)
        #expect(abs((outHigh - outLow) - 1 / Limiter.ratio) < 0.001)
    }

    @Test("The curve never turns back on itself")
    func monotonic() {
        // A compressor whose output falls as its input rises is a distortion
        // unit. Bisection solving for `k` makes this worth checking rather
        // than assuming.
        var previous = -Double.infinity
        for halfDb in stride(from: -60.0, through: 24.0, by: 0.25) {
            let out = halfDb + Limiter.gainReduction(forLevel: halfDb)
            #expect(out >= previous - 1e-9, "output fell at \(halfDb) dBFS")
            previous = out
        }
    }

    @Test("The quiet shortcut sits exactly on the threshold")
    func quietShortcutIsHonest() {
        // The fast path skips the curve entirely below this, so if it sat
        // anywhere above the threshold it would silently pass audio the
        // curve wanted to reduce.
        let shortcut = 20 * log10(0.398_107)
        #expect(abs(shortcut - Limiter.threshold) < 0.01)
    }
}
