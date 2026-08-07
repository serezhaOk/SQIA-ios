// Barely-there space: a quiet, darkened slap every sample hit feeds into.
// Subtle by design — felt more than heard.
//
// Port of the send effect in the web app's src/audio.ts: a 170 ms delay with
// its feedback path rolled off at 2.4 kHz, fed at 0.16 and folding back on
// itself at 0.28. Stereo, because Web Audio nodes take the channel count of
// what feeds them and the samples are all stereo — one delay line per side,
// with no crossfeed.

public struct SlapDelay: Sendable {
    public static let sendGain = 0.16
    public static let delayTime = 0.17
    public static let dampingFrequency = 2400.0
    public static let feedback = 0.28

    private var lineLeft: DelayLine
    private var lineRight: DelayLine
    private var dampLeft: Biquad
    private var dampRight: Biquad
    /// What the feedback path will add to the next input sample.
    private var pendingLeft: Double = 0
    private var pendingRight: Double = 0

    public init(sampleRate: Double) {
        lineLeft = DelayLine(maximum: 1, delay: Self.delayTime, sampleRate: sampleRate)
        lineRight = DelayLine(maximum: 1, delay: Self.delayTime, sampleRate: sampleRate)
        dampLeft = Biquad(lowpass: Self.dampingFrequency, sampleRate: sampleRate)
        dampRight = Biquad(lowpass: Self.dampingFrequency, sampleRate: sampleRate)
    }

    public mutating func clear() {
        lineLeft.clear()
        lineRight.clear()
        dampLeft.reset()
        dampRight.reset()
        pendingLeft = 0
        pendingRight = 0
    }

    /// Feed one dry frame in; get back what the send contributes to the mix.
    ///
    /// The web wires this as delay → damp → (feedback → delay) and taps the
    /// damped signal for the output, so the first echo is already filtered.
    public mutating func process(
        left: Double,
        right: Double
    ) -> (left: Double, right: Double) {
        let delayedLeft = lineLeft.process(left * Self.sendGain + pendingLeft)
        let dampedLeft = dampLeft.process(delayedLeft)
        pendingLeft = dampedLeft * Self.feedback

        let delayedRight = lineRight.process(right * Self.sendGain + pendingRight)
        let dampedRight = dampRight.process(delayedRight)
        pendingRight = dampedRight * Self.feedback

        return (dampedLeft, dampedRight)
    }
}
