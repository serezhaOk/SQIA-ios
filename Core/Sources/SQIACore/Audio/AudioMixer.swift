// The render core: everything that turns scheduled notes into samples.
//
// The web builds a Tone node per note and throws it away after the tail; at
// two dense tracks that is around thirty a second, which is nothing in a
// browser. AVAudioEngine nodes are not that cheap, and attaching one is not
// safe to do while audio is running. So the graph on this side is a single
// source node, and everything inside it — voices, each preset's chain, the
// room they share, the limiter — lives here, where it is ordinary code that
// can be tested off a device.
//
// The signal follows the web's: voices sum into their preset's own chain
// (filter → overdrive → chorus → ping-pong delay), each chain goes dry to
// the master and sends into one shared reverb, and the master runs at 0.9
// into the limiter.
//
// Nothing in `render` allocates, locks or touches a reference count.

import CSQIAAtomics
import Dispatch

public final class AudioMixer: @unchecked Sendable {
    /// The master gain the web app runs at, before the limiter.
    public static let masterGain = 0.9
    /// Voice budget, so a busy pattern cannot melt a phone. The web app
    /// drops notes past this rather than stealing voices, and so does this.
    public static let defaultVoiceLimit = 40

    public let events: AudioEventQueue
    public let sampleRate: Double

    private var voices: [SynthVoice]
    /// One per preset, indexed by its raw value.
    private var chains: [PresetChain]
    /// Where each preset's voices sum before their chain sees them.
    private var buses: [Double]
    private var reverb: Reverb
    private var limiter: Limiter

    /// Frames rendered since the mixer started — the clock events are
    /// scheduled against. Owned by the render thread.
    public private(set) var frame: Int64 = 0

    /// The same count, published for other threads to read.
    ///
    /// The transport needs to know what the audio clock says in order to
    /// schedule ahead of it, and it runs on a timer, not on the render
    /// thread. Reading `frame` directly from there would be a race; this is
    /// the same number, stored with release ordering once per block.
    private let publishedFrame: UnsafeMutablePointer<SQIAAtomicUInt64>

    public var currentFrame: Int64 {
        Int64(bitPattern: SQIAAtomicLoadAcquire(publishedFrame))
    }

    /// Diagnostics. Neither should move in normal use; both are worth
    /// watching on an old device with a full pattern.
    public private(set) var droppedNotes = 0
    public private(set) var queueOverflows = 0
    private var blowups = 0

    /// What the last blocks cost, as a fraction of the time they had to be
    /// ready in. Published for the UI, which is not the render thread.
    ///
    /// A crackle is a deadline missed, and from a desk there is no way to
    /// know whether a phone is missing them. This is the number that says so:
    /// comfortably under 0.2 and the sound is safe, near 1.0 and it cannot
    /// work. It holds a peak for a second and a half so a spike is still on
    /// screen by the time anyone looks up.
    private let publishedLoad: UnsafeMutablePointer<SQIAAtomicUInt64>
    private var loadPeak = 0.0

    public var renderLoad: Double {
        Double(bitPattern: SQIAAtomicLoadRelaxed(publishedLoad))
    }

    /// Both render-thread counters in one word — blowups in the high half,
    /// dropped notes in the low — so the UI can read them without racing the
    /// thread that writes them.
    ///
    /// A blowup should never happen: it means the output went non-finite and
    /// the effects had to be cleared out from under it. Dropped notes are
    /// ordinary at density, and the web drops them too.
    private let publishedFaults: UnsafeMutablePointer<SQIAAtomicUInt64>

    public var recoveredBlowups: Int {
        Int(SQIAAtomicLoadRelaxed(publishedFaults) >> 32)
    }

    public var droppedNoteCount: Int {
        Int(SQIAAtomicLoadRelaxed(publishedFaults) & 0xFFFF_FFFF)
    }

    private var nextEvent: AudioEvent?

    /// One past the highest voice slot that might be sounding. Scanning all
    /// forty every sample costs more than everything they play.
    private var activeHigh = 0
    /// Frames of silence out of the reverb, and out of the master. Both stop
    /// being computed once they are spent — an idle app should cost nothing.
    private var reverbRinging = 0
    private var masterQuiet = 0
    /// Long enough to cover the limiter's lookahead and any tail worth
    /// hearing.
    private static let ringOutFrames = 4_800

    public init(
        sampleRate: Double,
        voiceLimit: Int = defaultVoiceLimit,
        queueCapacity: Int = 512
    ) {
        self.sampleRate = sampleRate
        voices = Array(repeating: SynthVoice(), count: max(1, voiceLimit))
        chains = SynthPreset.allCases.map {
            PresetChain(preset: $0, sampleRate: sampleRate)
        }
        buses = Array(repeating: 0, count: SynthPreset.allCases.count)
        reverb = Reverb(sampleRate: sampleRate)
        limiter = Limiter(sampleRate: sampleRate)
        events = AudioEventQueue(capacity: queueCapacity)
        publishedFrame = .allocate(capacity: 1)
        SQIAAtomicInit(publishedFrame, 0)
        publishedLoad = .allocate(capacity: 1)
        SQIAAtomicInit(publishedLoad, 0)
        publishedFaults = .allocate(capacity: 1)
        SQIAAtomicInit(publishedFaults, 0)
    }

    deinit {
        publishedFrame.deallocate()
        publishedLoad.deallocate()
        publishedFaults.deallocate()
    }

    private func publishFrame() {
        SQIAAtomicStoreRelease(publishedFrame, UInt64(bitPattern: frame))
    }

    private func publishFaults() {
        let packed = UInt64(UInt32(truncatingIfNeeded: blowups)) << 32
            | UInt64(UInt32(truncatingIfNeeded: droppedNotes))
        SQIAAtomicStoreRelease(publishedFaults, packed)
    }

    public var activeVoiceCount: Int {
        voices.reduce(0) { $0 + ($1.isActive ? 1 : 0) }
    }

    /// Schedule an event. Safe to call from any one thread that is not the
    /// render thread.
    @discardableResult
    public func schedule(_ event: AudioEvent) -> Bool {
        let accepted = events.push(event)
        if !accepted { queueOverflows += 1 }
        return accepted
    }

    /// Silence everything at once, without waiting for tails.
    public func panic() {
        schedule(AudioEvent(kind: .silence, frame: 0))
    }

    /// Render one block. Called on the audio thread and nowhere else.
    public func render(
        frameCount: Int,
        left: UnsafeMutablePointer<Float>,
        right: UnsafeMutablePointer<Float>
    ) {
        let started = DispatchTime.now().uptimeNanoseconds

        for i in 0..<frameCount {
            let now = frame + Int64(i)

            // Fire everything due at or before this frame. An event whose
            // time has already passed still fires: better a note a fraction
            // late than a note missing.
            if nextEvent == nil { nextEvent = events.pop() }
            while let event = nextEvent, event.frame <= now {
                apply(event)
                nextEvent = events.pop()
            }

            // Nothing sounding and nothing left ringing: there is no
            // arithmetic that would produce anything but zero.
            if activeHigh == 0 && masterQuiet >= Self.ringOutFrames {
                left[i] = 0
                right[i] = 0
                continue
            }

            // Voices are mono; the stereo comes from the chains.
            for b in buses.indices { buses[b] = 0 }
            for v in 0..<activeHigh where voices[v].isActive {
                buses[voices[v].preset.rawValue] += voices[v].render()
            }

            var dryLeft = 0.0
            var dryRight = 0.0
            var sendLeft = 0.0
            var sendRight = 0.0

            for c in chains.indices {
                let bus = buses[c]
                // A preset nobody is playing is not worth a filter, a
                // chorus and two delay lines every sample.
                if bus == 0 && !chains[c].isRinging { continue }
                let out = chains[c].process(left: bus, right: bus)
                dryLeft += out.left
                dryRight += out.right
                sendLeft += out.left * out.send
                sendRight += out.right * out.send
            }

            if sendLeft != 0 || sendRight != 0 {
                reverbRinging = Self.ringOutFrames
            }
            if reverbRinging > 0 {
                reverbRinging -= 1
                let room = reverb.process(left: sendLeft, right: sendRight)
                dryLeft += room.left
                dryRight += room.right
            }

            let out = limiter.process(
                left: dryLeft * Self.masterGain, right: dryRight * Self.masterGain)

            // One test covers both channels for NaN and for either infinity:
            // adding them keeps a NaN, and an infinity either survives or
            // meets its opposite and becomes one.
            guard (out.left + out.right).isFinite else {
                left[i] = 0
                right[i] = 0
                recoverFromBlowup()
                continue
            }

            // The speaker cannot play past full scale, and a sample that asks
            // to is the loudest crackle there is. The limiter should have
            // caught it; this is the floor under that.
            left[i] = Float(min(max(out.left, -1), 1))
            right[i] = Float(min(max(out.right, -1), 1))

            if abs(out.left) + abs(out.right) > 1e-7 {
                masterQuiet = 0
            } else if masterQuiet < Self.ringOutFrames {
                masterQuiet += 1
            }
        }

        frame += Int64(frameCount)
        // Pull the watermark back down so the next block only walks the
        // slots that are still in use.
        while activeHigh > 0 && !voices[activeHigh - 1].isActive { activeHigh -= 1 }
        publishFrame()
        publishLoad(started: started, frameCount: frameCount)
    }

    /// A filter has gone unstable and is feeding infinities down the bus.
    ///
    /// Everything with memory gets emptied — voices included, since whichever
    /// one caused it would only do it again — and the count says it happened.
    /// The alternative is a renderer that roars until the app is killed.
    private func recoverFromBlowup() {
        for v in voices.indices { voices[v].stop() }
        for c in chains.indices { chains[c].clear() }
        reverb.clear()
        limiter.clear()
        activeHigh = 0
        reverbRinging = 0
        masterQuiet = Self.ringOutFrames
        blowups += 1
        publishFaults()
    }

    /// Seconds of work per second of audio, held at its peak for a moment.
    private func publishLoad(started: UInt64, frameCount: Int) {
        let elapsed = Double(DispatchTime.now().uptimeNanoseconds &- started) / 1_000_000_000
        let block = Double(frameCount) / sampleRate
        guard block > 0 else { return }

        // Decays to nothing over a second and a half, so a spike is still
        // readable but a stale one does not linger.
        loadPeak = max(elapsed / block, loadPeak * max(0, 1 - block / 1.5))
        SQIAAtomicStoreRelease(publishedLoad, loadPeak.bitPattern)
    }

    private func apply(_ event: AudioEvent) {
        switch event.kind {
        case .silence:
            for v in voices.indices { voices[v].stop() }
            for c in chains.indices { chains[c].clear() }
            reverb.clear()
            limiter.clear()
            activeHigh = 0
            reverbRinging = 0
            masterQuiet = Self.ringOutFrames

        case .presetDrift:
            let index = event.drift.preset.rawValue
            guard chains.indices.contains(index) else { return }
            chains[index].apply(event.drift)

        case .synthNote:
            guard let slot = voices.firstIndex(where: { !$0.isActive }) else {
                droppedNotes += 1
                publishFaults()
                return
            }
            voices[slot].start(event.recipe, sampleRate: sampleRate)
            if slot >= activeHigh { activeHigh = slot + 1 }
            masterQuiet = 0
        }
    }

    /// Which subdivision a preset's echo currently sits on. The transport
    /// needs it to decide whether to re-roll, and reading it between blocks
    /// is close enough — the answer only changes once a bar.
    public func echoDivision(of preset: SynthPreset) -> Int {
        let index = preset.rawValue
        return chains.indices.contains(index) ? chains[index].division : 0
    }

    /// Restart the frame clock. Only meaningful while stopped — after the
    /// engine has been torn down and rebuilt, say.
    public func reset() {
        frame = 0
        publishFrame()
        nextEvent = nil
        while events.pop() != nil {}
        for v in voices.indices { voices[v].stop() }
        for c in chains.indices { chains[c].clear() }
        reverb.clear()
        limiter.clear()
        activeHigh = 0
        reverbRinging = 0
        masterQuiet = Self.ringOutFrames
        droppedNotes = 0
        queueOverflows = 0
        blowups = 0
        publishFaults()
        loadPeak = 0
        SQIAAtomicStoreRelease(publishedLoad, 0)
    }
}
