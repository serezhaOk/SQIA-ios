// A fixed delay line: write a sample, read one back from N samples ago.
//
// The buffer is allocated once at the sample rate it will run at, so the
// render thread never allocates.

public struct DelayLine: Sendable {
    private var buffer: [Double]
    private var writeIndex = 0
    private var delaySamples: Int

    /// - Parameters:
    ///   - maximum: longest delay the line will ever be asked for, seconds.
    ///   - delay: the delay to start at, seconds.
    public init(maximum: Double, delay: Double, sampleRate: Double) {
        let capacity = max(2, Int((maximum * sampleRate).rounded(.up)) + 1)
        buffer = Array(repeating: 0, count: capacity)
        delaySamples = 0
        setDelay(delay, sampleRate: sampleRate)
    }

    public mutating func setDelay(_ seconds: Double, sampleRate: Double) {
        let samples = Int((seconds * sampleRate).rounded())
        delaySamples = min(max(samples, 1), buffer.count - 1)
    }

    public mutating func clear() {
        for i in buffer.indices { buffer[i] = 0 }
        writeIndex = 0
    }

    /// Push one sample in and take the delayed one out.
    public mutating func process(_ x: Double) -> Double {
        var readIndex = writeIndex - delaySamples
        if readIndex < 0 { readIndex += buffer.count }
        let y = buffer[readIndex]
        buffer[writeIndex] = x
        writeIndex += 1
        if writeIndex == buffer.count { writeIndex = 0 }
        return y
    }
}
