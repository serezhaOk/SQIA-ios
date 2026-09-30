import SQIASound
import XCTest

final class SQIASoundTests: XCTestCase {
    private var synth: OpaquePointer!

    override func setUp() {
        synth = sqia_synth_create()
    }

    override func tearDown() {
        sqia_synth_destroy(synth)
    }

    private func set(_ param: SQIAParam, _ value: Float) {
        sqia_synth_set_param(synth, Int32(param.rawValue), value)
    }

    /// Renders in the odd-sized chunks a real audio callback asks for.
    private func render(seconds: Double) -> (left: [Float], right: [Float]) {
        let total = Int(seconds * Double(SQIA_SAMPLE_RATE))
        var left = [Float](repeating: 0, count: total)
        var right = [Float](repeating: 0, count: total)
        var offset = 0
        while offset < total {
            let n = min(471, total - offset)
            left.withUnsafeMutableBufferPointer { l in
                right.withUnsafeMutableBufferPointer { r in
                    sqia_synth_render(synth, l.baseAddress! + offset, r.baseAddress! + offset, Int32(n))
                }
            }
            offset += n
        }
        return (left, right)
    }

    func testA4IsFourHundredAndFortyHertz() {
        // Two-operator FM with no modulation is a plain sine.
        set(SQIA_PARAM_ENGINE, 10)
        set(SQIA_PARAM_TIMBRE, 0)
        set(SQIA_PARAM_MORPH, 0.5)
        set(SQIA_PARAM_AMP_MODE, Float(SQIA_AMP_ADSR.rawValue))
        set(SQIA_PARAM_SUSTAIN, 1)
        set(SQIA_PARAM_REVERB_MIX, 0)
        sqia_synth_note_on(synth, 69, 1)
        let signal = render(seconds: 1.2).left.dropFirst(24_000)

        // Rising zero crossings, located to a fraction of a sample.
        var crossings: [Double] = []
        var previous = signal.first!
        for (i, x) in signal.enumerated().dropFirst() {
            if previous < 0, x >= 0 {
                crossings.append(Double(i - 1) + Double(-previous / (x - previous)))
            }
            previous = x
        }
        let period = (crossings.last! - crossings.first!) / Double(crossings.count - 1)
        let frequency = Double(SQIA_SAMPLE_RATE) / period
        XCTAssertEqual(frequency, 440, accuracy: 0.3)
    }

    func testResampledToAnotherRateStaysInTune() {
        // A route at 44.1 kHz: the synth still runs at 48 and resamples.
        let resampled = sqia_synth_create_at(44_100)!
        defer { sqia_synth_destroy(resampled) }
        for (param, value) in [
            (SQIA_PARAM_ENGINE, Float(10)), (SQIA_PARAM_TIMBRE, 0), (SQIA_PARAM_MORPH, 0.5),
            (SQIA_PARAM_AMP_MODE, Float(SQIA_AMP_ADSR.rawValue)), (SQIA_PARAM_SUSTAIN, 1),
            (SQIA_PARAM_REVERB_MIX, 0),
        ] {
            sqia_synth_set_param(resampled, Int32(param.rawValue), value)
        }
        sqia_synth_note_on(resampled, 69, 1)
        var left = [Float](repeating: 0, count: 44_100)
        var right = left
        sqia_synth_render(resampled, &left, &right, Int32(left.count))
        let signal = left.dropFirst(22_050)

        var crossings: [Double] = []
        var previous = signal.first!
        for (i, x) in signal.enumerated().dropFirst() {
            if previous < 0, x >= 0 {
                crossings.append(Double(i - 1) + Double(-previous / (x - previous)))
            }
            previous = x
        }
        let period = (crossings.last! - crossings.first!) / Double(crossings.count - 1)
        XCTAssertEqual(44_100 / period, 440, accuracy: 0.3)
    }

    func testTimedNoteReleasesItself() {
        set(SQIA_PARAM_ENGINE, 10)
        set(SQIA_PARAM_AMP_MODE, Float(SQIA_AMP_ADSR.rawValue))
        set(SQIA_PARAM_RELEASE, 0.02)
        set(SQIA_PARAM_REVERB_MIX, 0)
        sqia_synth_note_on_for(synth, 60, 1, 0.1)
        _ = render(seconds: 0.05)
        XCTAssertEqual(sqia_synth_active_voices(synth), 1)
        _ = render(seconds: 0.3)
        XCTAssertEqual(sqia_synth_active_voices(synth), 0)
    }

    func testEveryEngineSoundsAndFallsSilent() {
        set(SQIA_PARAM_AMP_MODE, Float(SQIA_AMP_ADSR.rawValue))
        set(SQIA_PARAM_RELEASE, 0.05)
        set(SQIA_PARAM_REVERB_MIX, 0)
        for engine in 0..<Int(SQIA_ENGINE_COUNT) {
            set(SQIA_PARAM_ENGINE, Float(engine))
            sqia_synth_note_on(synth, 48, 0.9)
            let held = render(seconds: 0.4)
            sqia_synth_note_off(synth, 48)
            _ = render(seconds: 0.5)
            let key = String(cString: sqia_engine_key(Int32(engine)))

            XCTAssertTrue(held.left.allSatisfy(\.isFinite), "\(key) produced a NaN")
            let peak = held.left.map(abs).max()!
            XCTAssertGreaterThan(peak, 0.01, "\(key) is silent")
            XCTAssertLessThanOrEqual(peak, 1, "\(key) escaped the ceiling")
            XCTAssertEqual(sqia_synth_active_voices(synth), 0, "\(key) never retired")
        }
    }

    func testStealsRatherThanExceedingPolyphony() {
        set(SQIA_PARAM_POLYPHONY, 4)
        for note in 60..<70 {
            sqia_synth_note_on(synth, Int32(note), 0.8)
            _ = render(seconds: 0.01)
        }
        _ = render(seconds: 0.05)
        XCTAssertEqual(sqia_synth_active_voices(synth), 4)
    }

    func testSpreadRollsEachNoteDifferently() {
        // With level spread, repeated identical notes come out at different
        // loudnesses.
        set(SQIA_PARAM_ENGINE, 10)
        set(SQIA_PARAM_AMP_MODE, Float(SQIA_AMP_ADSR.rawValue))
        set(SQIA_PARAM_REVERB_MIX, 0)
        set(SQIA_PARAM_RELEASE, 0.01)
        sqia_synth_set_spread(synth, Int32(SQIA_PARAM_LEVEL.rawValue), 0.5)
        var peaks: Set<Int> = []
        for _ in 0..<6 {
            sqia_synth_note_on(synth, 60, 1)
            let out = render(seconds: 0.1)
            sqia_synth_note_off(synth, 60)
            _ = render(seconds: 0.1)
            peaks.insert(Int(out.left.map(abs).max()! * 1000))
        }
        XCTAssertGreaterThan(peaks.count, 3)
    }

    func testEightVoicesOfTheHeaviestEngineFitInRealtime() {
        var worst = (engine: "", load: 0.0)
        for engine in 0..<Int(SQIA_ENGINE_COUNT) {
            set(SQIA_PARAM_ENGINE, Float(engine))
            for note in [48, 52, 55, 59, 62, 65, 69, 72] {
                sqia_synth_note_on(synth, Int32(note), 0.8)
            }
            let seconds = 1.0
            let start = Date()
            _ = render(seconds: seconds)
            let load = Date().timeIntervalSince(start) / seconds
            if load > worst.load { worst = (String(cString: sqia_engine_key(Int32(engine))), load) }
            sqia_synth_panic(synth)
            _ = render(seconds: 0.01)
        }
        print("Heaviest: \(worst.engine) at \(Int(worst.load * 100))% of one core")
        XCTAssertLessThan(worst.load, 0.5)
    }

    func testSequencerStepsOnTheSixteenth() {
        // At 120 BPM a sixteenth is 6000 samples. One accent on step 4 only.
        set(SQIA_PARAM_ENGINE, 10)
        set(SQIA_PARAM_AMP_MODE, Float(SQIA_AMP_ADSR.rawValue))
        set(SQIA_PARAM_ATTACK, 0.001)
        set(SQIA_PARAM_REVERB_MIX, 0)
        sqia_seq_set_cell(synth, 4, 0, 1)
        sqia_seq_set_row_note(synth, 0, 69)
        sqia_seq_set_tempo(synth, 120)
        sqia_seq_set_playing(synth, true)

        let out = render(seconds: 0.6).left
        let onset = out.firstIndex { abs($0) > 0.01 }!
        // Plaits delays its trigger by 5 blocks (1.25 ms) on purpose.
        XCTAssertEqual(Double(onset), 24_000 + 60, accuracy: 120)
        XCTAssertEqual(sqia_seq_position(synth), 4)

        sqia_seq_set_playing(synth, false)
        _ = render(seconds: 0.01)
        XCTAssertEqual(sqia_seq_position(synth), -1)
    }

    // ------------------------------------------------------------ samples --

    private func frequency(of signal: ArraySlice<Float>, rate: Double) -> Double {
        var crossings: [Double] = []
        var previous = signal.first!
        for (i, x) in signal.enumerated().dropFirst() {
            if previous < 0, x >= 0 {
                crossings.append(Double(i - 1) + Double(-previous / (x - previous)))
            }
            previous = x
        }
        let period = (crossings.last! - crossings.first!) / Double(crossings.count - 1)
        return rate / period
    }

    private func sine(_ hz: Double, rate: Double, seconds: Double) -> [Float] {
        (0..<Int(rate * seconds)).map { Float(0.5 * sin(2 * .pi * hz * Double($0) / rate)) }
    }

    private func useSamples(_ build: (OpaquePointer) -> Void) {
        let samples = sqia_samples_create()!
        build(samples)
        sqia_synth_set_samples(synth, samples)
        set(SQIA_PARAM_SOURCE, Float(SQIA_SOURCE_SAMPLES.rawValue))
        set(SQIA_PARAM_AMP_MODE, Float(SQIA_AMP_ADSR.rawValue))
        set(SQIA_PARAM_SUSTAIN, 1)
        set(SQIA_PARAM_REVERB_MIX, 0)
    }

    func testASampleIsRepitchedToTheNote() {
        // A4 recorded at 44.1 kHz, played an octave up.
        let a4 = sine(440, rate: 44_100, seconds: 2)
        useSamples { set in
            let i = sqia_samples_add(set, a4, nil, Int32(a4.count), 44_100)
            sqia_samples_map(set, i, 0, 127, 69)
        }
        sqia_synth_note_on(synth, 81, 1)
        let out = render(seconds: 0.6).left
        XCTAssertEqual(frequency(of: out[4_800...], rate: 48_000), 880, accuracy: 0.5)
    }

    func testKeyTrackOffPlaysTheRecordingAsIs() {
        let a4 = sine(440, rate: 48_000, seconds: 2)
        useSamples { set in
            let i = sqia_samples_add(set, a4, nil, Int32(a4.count), 48_000)
            sqia_samples_map(set, i, 0, 127, 69)
        }
        set(SQIA_PARAM_KEY_TRACK, 0)
        sqia_synth_note_on(synth, 50, 1)
        let out = render(seconds: 0.6).left
        XCTAssertEqual(frequency(of: out[4_800...], rate: 48_000), 440, accuracy: 0.5)
    }

    func testOverlappingZonesTakeTurnsAtRandom() {
        // Two takes of the same note: one positive, one negative.
        let up = [Float](repeating: 0.5, count: 4_800)
        let down = [Float](repeating: -0.5, count: 4_800)
        useSamples { set in
            sqia_samples_map(set, sqia_samples_add(set, up, nil, 4_800, 48_000), 60, 60, 60)
            sqia_samples_map(set, sqia_samples_add(set, down, nil, 4_800, 48_000), 60, 60, 60)
        }
        var signs: Set<Bool> = []
        for _ in 0..<20 {
            sqia_synth_note_on(synth, 60, 1)
            let out = render(seconds: 0.05).left
            signs.insert(out[1_000] > 0)
            sqia_synth_panic(synth)
            _ = render(seconds: 0.01)
        }
        XCTAssertEqual(signs, [true, false])
    }

    func testAPingedSamplePlaysToItsEndAndRetires() {
        let hit = sine(200, rate: 48_000, seconds: 0.2)
        useSamples { set in
            sqia_samples_map(set, sqia_samples_add(set, hit, nil, Int32(hit.count), 48_000), 0, 127, 60)
        }
        set(SQIA_PARAM_AMP_MODE, Float(SQIA_AMP_PING.rawValue))
        sqia_synth_note_on(synth, 60, 1)
        sqia_synth_note_off(synth, 60)
        let out = render(seconds: 0.15).left
        XCTAssertGreaterThan(out.map(abs).max()!, 0.1, "a key let go at once still plays")
        _ = render(seconds: 0.2)
        XCTAssertEqual(sqia_synth_active_voices(synth), 0)
    }

    func testPitchedLayoutSplitsBetweenRootsAndSharesTakes() {
        // Three recordings: C4, and two takes of E4. Each is a constant so
        // the output says which one played.
        let values: [Float] = [0.1, 0.2, 0.3]
        useSamples { samples in
            for v in values {
                let flat = [Float](repeating: v, count: 4_800)
                _ = sqia_samples_add(samples, flat, nil, 4_800, 48_000)
            }
            sqia_samples_lay_out(samples, SQIA_LAYOUT_PITCHED, [60, 64, 64.2])
        }
        func played(_ note: Int32) -> Float {
            sqia_synth_note_on(synth, note, 1)
            let out = render(seconds: 0.03).left
            sqia_synth_panic(synth)
            _ = render(seconds: 0.01)
            return ((out[1_000] * 10).rounded()) / 10
        }
        set(SQIA_PARAM_LEVEL, 0)
        set(SQIA_PARAM_PAN, 0)
        // Constants pass the filter untouched; the pan law is unity at
        // centre, so the level comes straight through.
        XCTAssertEqual(played(20), 0.1)
        XCTAssertEqual(played(61), 0.1)
        XCTAssertEqual(played(62), 0.1)
        var upper: Set<Float> = []
        for _ in 0..<20 { upper.insert(played(63)) }
        XCTAssertEqual(upper, [0.2, 0.3])
    }

    func testSwappingSamplesWhilePlayingIsSafe() {
        let tone = sine(300, rate: 48_000, seconds: 1)
        for _ in 0..<12 {
            useSamples { set in
                sqia_samples_map(set, sqia_samples_add(set, tone, tone, Int32(tone.count), 48_000), 0, 127, 60)
            }
            sqia_synth_note_on(synth, 64, 1)
            _ = render(seconds: 0.02)
        }
        sqia_synth_set_samples(synth, nil)
        _ = render(seconds: 0.02)
        XCTAssertEqual(sqia_synth_active_voices(synth), 0)
    }

    func testKeysAreUniqueAndStable() {
        var keys: Set<String> = []
        for i in 0..<Int32(SQIA_PARAM_COUNT.rawValue) {
            var info = SQIAParamInfo()
            XCTAssertTrue(sqia_param_info(i, &info))
            keys.insert(String(cString: info.key))
        }
        XCTAssertEqual(keys.count, Int(SQIA_PARAM_COUNT.rawValue))
        XCTAssertEqual(String(cString: sqia_engine_key(8)), "virtual_analog")
    }
}
