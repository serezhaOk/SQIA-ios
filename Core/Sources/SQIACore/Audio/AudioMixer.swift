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
// the master and sends into one shared reverb, the sum goes through the
// mixer's two knobs, and the master runs at 0.9 into the limiter.
//
// The Lab's sounds come in beside all that: each is a whole synth of its own
// in SQIASound — voices, envelopes and its own room — so its output joins
// the dry sum just ahead of the knobs and the limiter, as it left the Lab.
//
// Nothing in `render` allocates, locks or touches a reference count.

import CSQIAAtomics
import Dispatch
import SQIASound

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
    /// Where each preset's voices sum before their chain sees them. Stereo,
    /// because a tremolo is spread across the two sides and summing it to
    /// mono would cancel it exactly.
    private var busesLeft: [Double]
    private var busesRight: [Double]
    private var reverb: Reverb
    /// Delay and Scatter, over everything.
    private var effects: MasterEffects
    private var limiter: Limiter

    /// Sounds are numbered by voice index, and there is room for this many.
    public static let soundSlots = 256

    /// One synth per sound, by voice index, as the bits of its pointer.
    ///
    /// Sounds arrive while the audio runs — a download finishes, the
    /// catalogue names a new one — so the synth is built on the main thread
    /// and published here with a release store; the render thread picks it
    /// up with an acquire load when a note asks for it. A slot is filled
    /// once and never emptied while the mixer lives, so the render thread
    /// never holds a synth somebody else could free.
    private let soundTable: UnsafeMutablePointer<SQIAAtomicUInt64>
    /// Main thread: which recordings each installed sound was given, so
    /// installing it again does not copy them again.
    private var installedSamples: [Int: String] = [:]

    /// Frames each sound is still worth rendering for: topped up by every
    /// note, long enough for the longest release and its room to die away.
    /// A sound at zero is not rendered at all; the ones above zero are
    /// listed in `awake`, so a sample costs nothing for the rest.
    private var soundAwake: [Int]
    private var awake: [Int]
    private var awakeCount = 0
    private let soundRingOut: Int

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

    /// Everything the render thread counts, in one word — voices sounding in
    /// the low sixteen bits, blowups in the next sixteen, dropped notes in
    /// the high thirty-two — so the UI can read them without racing the
    /// thread that writes them.
    ///
    /// A blowup should never happen: it means the output went non-finite and
    /// the effects had to be cleared out from under it. Dropped notes are
    /// ordinary at density, and the web drops them too.
    private let publishedFaults: UnsafeMutablePointer<SQIAAtomicUInt64>
    private var liveVoices = 0

    /// Voices sounding as of the last block.
    public var soundingVoices: Int {
        Int(SQIAAtomicLoadRelaxed(publishedFaults) & 0xFFFF)
    }

    public var recoveredBlowups: Int {
        Int((SQIAAtomicLoadRelaxed(publishedFaults) >> 16) & 0xFFFF)
    }

    public var droppedNoteCount: Int {
        Int(SQIAAtomicLoadRelaxed(publishedFaults) >> 32)
    }

    private var nextEvent: AudioEvent?

    /// How loud each band of the output was over the last block, as the
    /// bits of one double each — for the mixer's wave. Written once a
    /// block, read whenever the screen draws.
    private var meter: BandMeter
    private var meterLevels = [Double](repeating: 0, count: BandMeter.bands)
    private let publishedBands: UnsafeMutablePointer<SQIAAtomicUInt64>

    /// Each band's RMS over the last block, low to high. Safe from any
    /// thread.
    public func bandLevel(_ band: Int) -> Double {
        guard band >= 0 && band < BandMeter.bands else { return 0 }
        return Double(bitPattern: SQIAAtomicLoadRelaxed(publishedBands + band))
    }

    /// The knobs, as the bits of one double each.
    ///
    /// Not an event: the queue has one writer, the transport, and a knob is
    /// turned on the main thread — sixty times a second under a finger. So
    /// the knobs are left here for the render thread to look at once a
    /// block, and only the newest position matters anyway.
    private let publishedEffects: UnsafeMutablePointer<SQIAAtomicUInt64>
    private var appliedEffects = EffectSettings()

    /// Where the mixer's knobs are. Safe from any thread.
    public func setEffects(_ settings: EffectSettings) {
        for effect in MasterEffect.allCases {
            SQIAAtomicStoreRelease(
                publishedEffects + effect.rawValue, settings[effect].bitPattern)
        }
    }

    private func pickUpEffects() {
        var settings = EffectSettings()
        for effect in MasterEffect.allCases {
            settings[effect] = Double(
                bitPattern: SQIAAtomicLoadAcquire(publishedEffects + effect.rawValue))
        }
        guard settings != appliedEffects else { return }
        appliedEffects = settings
        effects.apply(settings)
    }

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
        // Every slot gets its buffers now, at the rate it will run at, so
        // that starting a note on the render thread never allocates.
        for v in voices.indices { voices[v].prepare(sampleRate: sampleRate) }
        chains = SynthPreset.allCases.map {
            PresetChain(preset: $0, sampleRate: sampleRate)
        }
        busesLeft = Array(repeating: 0, count: SynthPreset.allCases.count)
        busesRight = Array(repeating: 0, count: SynthPreset.allCases.count)
        reverb = Reverb(sampleRate: sampleRate)
        effects = MasterEffects(sampleRate: sampleRate)
        limiter = Limiter(sampleRate: sampleRate)
        soundTable = .allocate(capacity: Self.soundSlots)
        for slot in 0..<Self.soundSlots { SQIAAtomicInit(soundTable + slot, 0) }
        soundAwake = Array(repeating: 0, count: Self.soundSlots)
        awake = Array(repeating: 0, count: Self.soundSlots)
        soundRingOut = Int(16 * sampleRate)
        meter = BandMeter(sampleRate: sampleRate)
        publishedBands = .allocate(capacity: BandMeter.bands)
        for band in 0..<BandMeter.bands { SQIAAtomicInit(publishedBands + band, 0) }
        events = AudioEventQueue(capacity: queueCapacity)
        publishedFrame = .allocate(capacity: 1)
        SQIAAtomicInit(publishedFrame, 0)
        publishedLoad = .allocate(capacity: 1)
        SQIAAtomicInit(publishedLoad, 0)
        publishedFaults = .allocate(capacity: 1)
        SQIAAtomicInit(publishedFaults, 0)
        publishedEffects = .allocate(capacity: MasterEffect.allCases.count)
        for effect in MasterEffect.allCases {
            SQIAAtomicInit(publishedEffects + effect.rawValue, 0)
        }
        // The bundle's sounds are there from the first note.
        for sound in Sound.bundled { install(sound, samples: nil) }
    }

    private func synth(_ id: Int) -> OpaquePointer? {
        guard id >= 0 && id < Self.soundSlots else { return nil }
        return OpaquePointer(bitPattern: UInt(SQIAAtomicLoadAcquire(soundTable + id)))
    }

    /// Makes a sound playable, or brings it up to date. Main thread only.
    ///
    /// A sound made of recordings needs them: install it once they are on
    /// the phone and decoded, not before. Installing again with new knobs
    /// changes them under notes that are playing, which the knobs allow.
    public func install(_ sound: Sound, samples: SampleSet?) {
        guard sound.id >= 0 && sound.id < Self.soundSlots else { return }
        let existing = synth(sound.id)
        guard let target = existing ?? sqia_synth_create_at(sampleRate) else { return }
        sound.apply(to: target)
        if let manifest = sound.samples, let samples,
            installedSamples[sound.id] != manifest.folder
        {
            sqia_synth_set_samples(target, samples.make())
            installedSamples[sound.id] = manifest.folder
        }
        if existing == nil {
            SQIAAtomicStoreRelease(soundTable + sound.id, UInt64(UInt(bitPattern: target)))
        }
    }

    /// Whether a sound can be played on this mixer. Main thread only.
    public func isInstalled(_ sound: Sound) -> Bool {
        guard synth(sound.id) != nil else { return false }
        guard let manifest = sound.samples else { return true }
        return installedSamples[sound.id] == manifest.folder
    }

    deinit {
        for slot in 0..<Self.soundSlots {
            if let synth = synth(slot) { sqia_synth_destroy(synth) }
        }
        soundTable.deallocate()
        publishedFrame.deallocate()
        publishedLoad.deallocate()
        publishedFaults.deallocate()
        publishedEffects.deallocate()
        publishedBands.deallocate()
    }

    private func publishFrame() {
        SQIAAtomicStoreRelease(publishedFrame, UInt64(bitPattern: frame))
    }

    private func publishFaults() {
        let packed =
            UInt64(UInt32(truncatingIfNeeded: droppedNotes)) << 32
            | UInt64(UInt16(truncatingIfNeeded: blowups)) << 16
            | UInt64(UInt16(truncatingIfNeeded: liveVoices))
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
        pickUpEffects()

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

            var soundLeft = 0.0
            var soundRight = 0.0
            let soundsAwake = awakeCount > 0
            var a = awakeCount - 1
            while a >= 0 {
                let id = awake[a]
                if let synth = synth(id) {
                    var l: Float = 0
                    var r: Float = 0
                    sqia_synth_render(synth, &l, &r, 1)
                    soundLeft += Double(l)
                    soundRight += Double(r)
                }
                soundAwake[id] -= 1
                if soundAwake[id] <= 0 {
                    awakeCount -= 1
                    awake[a] = awake[awakeCount]
                }
                a -= 1
            }

            // Nothing sounding and nothing left ringing: there is no
            // arithmetic that would produce anything but zero.
            if activeHigh == 0 && !soundsAwake && masterQuiet >= Self.ringOutFrames {
                left[i] = 0
                right[i] = 0
                meter.skip(1)
                continue
            }

            for b in busesLeft.indices {
                busesLeft[b] = 0
                busesRight[b] = 0
            }
            for v in 0..<activeHigh where voices[v].isActive {
                let slot = voices[v].preset.rawValue
                let out = voices[v].render()
                busesLeft[slot] += out.left
                busesRight[slot] += out.right
            }

            var dryLeft = soundLeft
            var dryRight = soundRight
            var sendLeft = 0.0
            var sendRight = 0.0

            for c in chains.indices {
                let busLeft = busesLeft[c]
                let busRight = busesRight[c]
                // A preset nobody is playing is not worth a filter, a
                // chorus and two delay lines every sample.
                if busLeft == 0 && busRight == 0 && !chains[c].isRinging { continue }
                let out = chains[c].process(left: busLeft, right: busRight)
                dryLeft += out.left
                dryRight += out.right
                sendLeft += out.sendLeft
                sendRight += out.sendRight
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

            let mixed = effects.process(left: dryLeft, right: dryRight, frame: now)
            let out = limiter.process(
                left: mixed.left * Self.masterGain, right: mixed.right * Self.masterGain)

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
            meter.process((out.left + out.right) * 0.5)

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

        // Once a block, not once a sample: forty comparisons against a
        // thousand samples of work is nothing, and the UI wants the number.
        var live = 0
        for v in 0..<activeHigh where voices[v].isActive { live += 1 }
        for a in 0..<awakeCount {
            if let synth = synth(awake[a]) { live += Int(sqia_synth_active_voices(synth)) }
        }
        if live != liveVoices {
            liveVoices = live
            publishFaults()
        }

        meter.read(into: &meterLevels)
        for band in 0..<BandMeter.bands {
            SQIAAtomicStoreRelease(publishedBands + band, meterLevels[band].bitPattern)
        }

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
        silenceSounds()
        for c in chains.indices { chains[c].clear() }
        reverb.clear()
        effects.clear()
        limiter.clear()
        meter.clear()
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
            silenceSounds()
            for c in chains.indices { chains[c].clear() }
            reverb.clear()
            effects.clear()
            limiter.clear()
            activeHigh = 0
            reverbRinging = 0
            masterQuiet = Self.ringOutFrames

        case .room:
            reverb.retune(
                decay: event.room.decay, preDelay: event.room.preDelay,
                damping: event.room.damping)

        case .chain:
            let index = event.chain.preset.rawValue
            guard chains.indices.contains(index) else { return }
            chains[index].setSendHighpass(event.chain.sendHighpass)
            if event.chain.delayWet >= 0 {
                chains[index].setDelayWet(event.chain.delayWet)
            }

        case .grid:
            effects.apply(event.grid)

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

        case .soundNote:
            let note = event.sound
            // Not installed yet — its recordings still on their way. The
            // note is lost, which is all a silent track can do.
            guard let synth = synth(note.sound) else { return }
            // The synth's own queue: this thread is its only writer.
            sqia_synth_note_on_for(
                synth, Int32(note.midi), Float(note.velocity), Float(note.seconds))
            if soundAwake[note.sound] <= 0 {
                awake[awakeCount] = note.sound
                awakeCount += 1
            }
            soundAwake[note.sound] = soundRingOut
            masterQuiet = 0
        }
    }

    /// Everything the sounds are playing, tails and rooms, gone. The panic
    /// is picked up the next time a sound renders, ahead of any new note.
    private func silenceSounds() {
        for slot in 0..<Self.soundSlots {
            if let synth = synth(slot) { sqia_synth_panic(synth) }
            soundAwake[slot] = 0
        }
        awakeCount = 0
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
        silenceSounds()
        for c in chains.indices { chains[c].clear() }
        reverb.clear()
        effects.clear()
        limiter.clear()
        meter.clear()
        activeHigh = 0
        reverbRinging = 0
        masterQuiet = Self.ringOutFrames
        droppedNotes = 0
        queueOverflows = 0
        blowups = 0
        liveVoices = 0
        publishFaults()
        loadPeak = 0
        SQIAAtomicStoreRelease(publishedLoad, 0)
    }
}
