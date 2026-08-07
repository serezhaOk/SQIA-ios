// One sounding sample.
//
// A voice reads through a decoded buffer at whatever rate pitches it to its
// column, shaped by the one-shot envelope, and retires when the envelope
// runs out. Voices live in a fixed pool and hold no references, so starting
// and stopping one costs nothing on the render thread.

/// A decoded sample the renderer can read from.
///
/// Deliberately pointers rather than arrays: the render thread must not
/// touch reference counts, so the app decodes each file once into storage it
/// keeps for the process's lifetime — the same "load once, never evict" the
/// web app's cache does — and passes the raw spans.
///
/// Stereo, because every sample in the set is, and summing them to mono
/// would throw away the width the sounds were made with.
public struct SampleRef: @unchecked Sendable, Equatable {
    public let left: UnsafePointer<Float>?
    /// Nil for a mono source, which is then heard on both sides.
    public let right: UnsafePointer<Float>?
    public let frameCount: Int
    /// The rate the file was decoded at. Divided by the engine's rate, it
    /// corrects for a file that was not recorded at the output rate.
    public let sampleRate: Double

    public static let empty = SampleRef(
        left: nil, right: nil, frameCount: 0, sampleRate: 44_100)

    public init(
        left: UnsafePointer<Float>?,
        right: UnsafePointer<Float>?,
        frameCount: Int,
        sampleRate: Double
    ) {
        self.left = left
        self.right = right
        self.frameCount = frameCount
        self.sampleRate = sampleRate
    }

    public var duration: Double {
        sampleRate > 0 ? Double(frameCount) / sampleRate : 0
    }
}

public struct SampleVoice: Sendable {
    public private(set) var isActive = false

    private var sample = SampleRef.empty
    private var envelope = SampleEnvelope(peak: 1, release: 0.08)
    /// Read position in the source, in frames.
    private var position: Double = 0
    /// How far the read position advances per output frame.
    private var increment: Double = 1
    /// Frames since the note started, which is what the envelope is a
    /// function of.
    private var age: Int = 0
    private var lifetime: Int = 0
    private var inverseSampleRate: Double = 1 / 48_000

    public init() {}

    /// Begin a note. `rate` is the musical playback rate; the file's own
    /// sample rate is folded in on top of it.
    public mutating func start(
        sample: SampleRef,
        rate: Double,
        velocity: Double,
        releaseScale: Double,
        sampleRate: Double
    ) {
        guard sample.left != nil, sample.frameCount > 0, sampleRate > 0 else {
            isActive = false
            return
        }
        self.sample = sample
        inverseSampleRate = 1 / sampleRate
        increment = rate * (sample.sampleRate / sampleRate)

        let release = SampleEnvelope.release(
            bufferDuration: sample.duration, rate: rate, scale: releaseScale)
        envelope = SampleEnvelope(peak: velocity, release: release)

        position = 0
        age = 0
        lifetime = Int(envelope.duration * sampleRate)
        isActive = true
    }

    public mutating func stop() {
        isActive = false
        position = 0
        age = 0
    }

    /// The next output frame, or silence once the voice has finished.
    ///
    /// Linear interpolation between neighbouring frames, which is what a
    /// browser's buffer source does when its playback rate is not 1.
    public mutating func render() -> (left: Double, right: Double) {
        guard isActive, let leftChannel = sample.left else { return (0, 0) }

        let index = Int(position)
        if index >= sample.frameCount || age >= lifetime {
            stop()
            return (0, 0)
        }

        let fraction = position - Double(index)
        let next = index + 1
        let hasNext = next < sample.frameCount

        func read(_ channel: UnsafePointer<Float>) -> Double {
            let a = Double(channel[index])
            let b = hasNext ? Double(channel[next]) : 0
            return a + (b - a) * fraction
        }

        let l = read(leftChannel)
        let r = sample.right.map(read) ?? l
        let gain = envelope.value(at: Double(age) * inverseSampleRate)

        position += increment
        age += 1
        return (l * gain, r * gain)
    }
}
