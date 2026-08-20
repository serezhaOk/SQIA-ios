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
        let y = peek()
        push(x)
        return y
    }

    /// The sample due now, without writing anything.
    ///
    /// A feedback comb has to read before it knows what to write — what goes
    /// in is the input plus what just came out — so the two halves are
    /// separate as well as joined.
    public func peek() -> Double {
        var readIndex = writeIndex - delaySamples
        if readIndex < 0 { readIndex += buffer.count }
        return buffer[readIndex]
    }

    /// Write one sample and move on.
    public mutating func push(_ x: Double) {
        buffer[writeIndex] = x
        writeIndex += 1
        if writeIndex == buffer.count { writeIndex = 0 }
    }

    /// The same, but reading from a delay that can sit between samples and
    /// move while it plays — which is what a chorus is.
    public mutating func process(_ x: Double, delaySamples delay: Double) -> Double {
        let wanted = min(max(delay, 1), Double(buffer.count - 2))
        let whole = Int(wanted)
        let fraction = wanted - Double(whole)

        var first = writeIndex - whole
        if first < 0 { first += buffer.count }
        var second = first - 1
        if second < 0 { second += buffer.count }

        let y = buffer[first] + (buffer[second] - buffer[first]) * fraction
        buffer[writeIndex] = x
        writeIndex += 1
        if writeIndex == buffer.count { writeIndex = 0 }
        return y
    }
}
