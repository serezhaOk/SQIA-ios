// The meter the mixer's wave is drawn from.

import Foundation
import Testing

@testable import SQIACore

@Suite("Band meter")
struct BandMeterTests {
    private let rate = 48_000.0

    private func levels(of hz: Double, seconds: Double = 0.25) -> [Double] {
        var meter = BandMeter(sampleRate: rate)
        for i in 0..<Int(rate * seconds) {
            meter.process(sin(2 * .pi * hz * Double(i) / rate) * 0.5)
        }
        var out = [Double](repeating: 0, count: BandMeter.bands)
        meter.read(into: &out)
        return out
    }

    @Test("A tone lights the band it sits in, and the bands either side less")
    func toneLandsInItsBand() {
        for band in [0, 4, 8] {
            let out = levels(of: BandMeter.centre(band))
            let loudest = out.indices.max { out[$0] < out[$1] }
            #expect(loudest == band, "\(BandMeter.centre(band)) Hz peaked in band \(loudest ?? -1)")
            for other in out.indices where abs(other - band) >= 3 {
                #expect(out[other] < out[band] * 0.35)
            }
        }
    }

    @Test("Silence reads as nothing, and a read starts the average again")
    func silenceIsZero() {
        var meter = BandMeter(sampleRate: rate)
        meter.skip(1024)
        var out = [Double](repeating: 1, count: BandMeter.bands)
        meter.read(into: &out)
        #expect(out.allSatisfy { $0 == 0 })

        for i in 0..<4800 { meter.process(sin(Double(i) * 0.1)) }
        meter.read(into: &out)
        #expect(out.contains { $0 > 0 })
        meter.clear()
        meter.read(into: &out)
        #expect(out.allSatisfy { $0 == 0 })
    }

    @Test("The mixer publishes what it played")
    func mixerPublishes() {
        let mixer = AudioMixer(sampleRate: rate)
        #expect((0..<BandMeter.bands).allSatisfy { mixer.bandLevel($0) == 0 })
        #expect(mixer.bandLevel(-1) == 0 && mixer.bandLevel(BandMeter.bands) == 0)
    }
}
