// Reading a WAV file into floats, without AVFoundation.
//
// The core stays free of Apple frameworks so it builds and tests on Linux,
// and the sampled sounds it ships are plain PCM, which is a header and a
// block of numbers. 16-, 24- and 32-bit integers and 32-bit floats, any
// number of channels — the first two are kept.

import Foundation

public struct WaveFile: Sendable {
    public let sampleRate: Double
    public let left: [Float]
    /// Nil for mono.
    public let right: [Float]?

    public var frames: Int { left.count }

    public init?(data: Data) {
        let bytes = [UInt8](data)
        func u16(_ i: Int) -> Int { Int(bytes[i]) | Int(bytes[i + 1]) << 8 }
        func u32(_ i: Int) -> Int { u16(i) | u16(i + 2) << 16 }
        func tag(_ i: Int) -> String { String(decoding: bytes[i..<(i + 4)], as: UTF8.self) }

        guard bytes.count >= 12, tag(0) == "RIFF", tag(8) == "WAVE" else { return nil }

        var format = 0
        var channels = 0
        var rate = 0
        var bits = 0
        var body: Range<Int>?
        var at = 12
        while at + 8 <= bytes.count {
            let size = u32(at + 4)
            let start = at + 8
            let end = min(start + size, bytes.count)
            switch tag(at) {
            case "fmt " where size >= 16:
                format = u16(start)
                channels = u16(start + 2)
                rate = u32(start + 4)
                bits = u16(start + 14)
                // WAVE_FORMAT_EXTENSIBLE carries the real format in its
                // sub-format GUID, whose first two bytes are the old code.
                if format == 0xFFFE, size >= 26 { format = u16(start + 24) }
            case "data":
                body = start..<end
            default:
                break
            }
            // Chunks are padded to an even length.
            at = start + size + (size & 1)
        }

        guard let body, channels > 0, rate > 0,
            (format == 1 && [16, 24, 32].contains(bits)) || (format == 3 && bits == 32)
        else { return nil }

        let width = bits / 8
        let frameBytes = width * channels
        let count = body.count / frameBytes
        var left = [Float](repeating: 0, count: count)
        var right: [Float]? = channels > 1 ? [Float](repeating: 0, count: count) : nil

        func sample(_ i: Int) -> Float {
            switch (format, bits) {
            case (3, _):
                return Float(bitPattern: UInt32(u32(i)))
            case (_, 16):
                return Float(Int16(bitPattern: UInt16(u16(i)))) / 32_768
            case (_, 24):
                let raw = Int32(bytes[i]) | Int32(bytes[i + 1]) << 8 | Int32(bytes[i + 2]) << 16
                return Float((raw << 8) >> 8) / 8_388_608
            default:
                return Float(Int32(bitPattern: UInt32(u32(i)))) / 2_147_483_648
            }
        }

        for f in 0..<count {
            let at = body.lowerBound + f * frameBytes
            left[f] = sample(at)
            if right != nil { right![f] = sample(at + width) }
        }
        self.sampleRate = Double(rate)
        self.left = left
        self.right = right
    }
}
