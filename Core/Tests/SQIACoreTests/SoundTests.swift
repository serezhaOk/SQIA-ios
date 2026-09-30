// The Lab's sounds, as SQIA carries them.

import Foundation
import Testing

@testable import SQIACore

@Suite("Lab sounds")
struct SoundTests {
    @Test("Every sound in the catalogue is in the bundle and reads")
    func library() {
        #expect(Sound.library.map(\.name) == [
            "BEES", "Barefeet", "Dancing flower", "Garedener", "Samurai Walk", "Handpan",
        ])
        #expect(Sound.library.map(\.id) == Array(0..<6))
    }

    @Test("A sound keeps what the file says")
    func values() throws {
        let string = try #require(Sound.library.first { $0.name == "Samurai Walk" })
        // "string" is Plaits' model 19; amp mode "lpg" is 1.
        #expect(string.values[0] == 19)
        #expect(string.values[9] == 1)
        let bees = try #require(Sound.library.first { $0.name == "BEES" })
        #expect(bees.values[9] == 2)  // ping
    }

    @Test("Voice indices: the five synths keep theirs, the sounds follow")
    func voiceIndex() {
        #expect(TrackVoice(index: 0) == .synth(.reverie))
        #expect(TrackVoice(index: 4) == .synth(.machine))
        #expect(TrackVoice(index: 5) == .sound(0))
        #expect(TrackVoice(index: 9) == .sound(4))
        #expect(TrackVoice.sound(3).index == 8)
        #expect(TrackVoice(index: 10) == .sound(5))
        // Something a newer build wrote still opens.
        #expect(TrackVoice(index: 99) == .synth(.reverie))
    }

    @Test("The handpan brings its twelve recordings")
    func handpan() throws {
        let handpan = try #require(Sound.library.first { $0.name == "Handpan" })
        #expect(handpan.sampleSet == "hang it")
        let set = try #require(SampleSet.named("hang it"))
        #expect(set.recordings.count == 12)
        #expect(!set.kit)
        // 16-bit mono at 44.1 kHz, about four seconds each.
        for recording in set.recordings {
            #expect(recording.audio.sampleRate == 44_100)
            #expect(recording.audio.right == nil)
            #expect(recording.audio.frames > 100_000)
        }
    }

    @Test("A sound note plays through the mixer, at the device's rate", arguments: [48_000.0, 44_100.0])
    func mixerPlaysSound(rate: Double) {
        let mixer = AudioMixer(sampleRate: rate)
        for sound in Sound.library.indices {
            mixer.schedule(
                AudioEvent.sound(
                    SoundNote(sound: sound, midi: 57, velocity: 0.9, seconds: 0.1),
                    at: Int64(Double(sound) * 0.5 * rate)))
        }
        let frames = Int(3 * rate)
        var left = [Float](repeating: 0, count: frames)
        var right = left
        left.withUnsafeMutableBufferPointer { l in
            right.withUnsafeMutableBufferPointer { r in
                var offset = 0
                while offset < frames {
                    let n = min(512, frames - offset)
                    mixer.render(frameCount: n, left: l.baseAddress! + offset, right: r.baseAddress! + offset)
                    offset += n
                }
            }
        }
        #expect(left.allSatisfy { $0.isFinite })
        // Each sound is heard in its own half second.
        for sound in Sound.library.indices {
            let start = Int(Double(sound) * 0.5 * rate)
            let window = left[start..<(start + Int(0.3 * rate))]
            #expect((window.map(abs).max() ?? 0) > 0.01, "\(Sound.library[sound].name) is silent")
        }
    }
}


@Suite("WAV files")
struct WaveFileTests {
    private func wav(format: Int, bits: Int, channels: Int, rate: Int, body: [UInt8]) -> Data {
        func le(_ v: Int, _ n: Int) -> [UInt8] { (0..<n).map { UInt8((v >> (8 * $0)) & 0xFF) } }
        var fmt = le(format, 2) + le(channels, 2) + le(rate, 4)
        fmt += le(rate * channels * bits / 8, 4) + le(channels * bits / 8, 2) + le(bits, 2)
        var chunks: [UInt8] = Array("WAVE".utf8)
        // An unknown chunk of odd length first, to exercise the padding.
        chunks += Array("LIST".utf8) + le(3, 4) + [1, 2, 3, 0]
        chunks += Array("fmt ".utf8) + le(fmt.count, 4) + fmt
        chunks += Array("data".utf8) + le(body.count, 4) + body
        return Data(Array("RIFF".utf8) + le(chunks.count, 4) + chunks)
    }

    @Test("16-bit mono")
    func sixteen() throws {
        // 0, +half, −full
        let file = try #require(
            WaveFile(data: wav(format: 1, bits: 16, channels: 1, rate: 44_100, body: [0, 0, 0, 0x40, 0, 0x80])))
        #expect(file.sampleRate == 44_100)
        #expect(file.left == [0, 0.5, -1])
        #expect(file.right == nil)
    }

    @Test("24-bit stereo")
    func twentyFour() throws {
        // L = +half, R = −half
        let file = try #require(
            WaveFile(data: wav(format: 1, bits: 24, channels: 2, rate: 48_000, body: [0, 0, 0x40, 0, 0, 0xC0])))
        #expect(file.left == [0.5])
        #expect(file.right == [-0.5])
    }

    @Test("Not a WAV")
    func garbage() {
        #expect(WaveFile(data: Data("hello".utf8)) == nil)
    }
}
