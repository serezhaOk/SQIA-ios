// One sounding synth note.
//
// The web builds a Tone node per note and disposes of it after the tail.
// Here a voice is a slot in a fixed pool that a recipe is poured into, so
// starting one costs nothing and stopping one costs nothing.

import Foundation

public struct SynthVoice: Sendable {
    /// Inharmonic ratios of the classic analogue cymbal — six square
    /// partials that beat against each other instead of forming a pitch.
    static let metalRatios = [1.0, 1.483, 1.932, 2.546, 2.630, 3.897]

    public private(set) var isActive = false
    public private(set) var preset: SynthPreset = .reverie

    private var recipe = VoiceRecipe()
    private var amp = ADSR()
    private var pitch = PitchEnvelope(octaves: 0, decay: 0.05)
    private var filter = Biquad(lowpass: 20_000, sampleRate: 48_000)
    /// The second half of a −24 dB an octave cascade, used only when the
    /// recipe asks for one.
    private var filterB = Biquad(lowpass: 20_000, sampleRate: 48_000)
    /// The 303's sweep. Tone scales it linearly between the base frequency
    /// and `octaves` above, through a square — so the envelope's own shape
    /// is what the cutoff traces.
    private var filterEnvelope = ADSR()
    private var oscillator = Oscillator()
    private var noise = Noise()
    /// Built once per slot, because its delay line is the only thing in a
    /// voice that allocates and the render thread must never do that.
    private var pluck = Pluck(sampleRate: 48_000)

    /// The FM pair, and the envelope that decides how far the modulator
    /// bends the carrier. An electric piano's bell is that envelope opening
    /// and shutting faster than the note it sits on.
    private var carrier = Oscillator(waveform: .sine)
    private var modulator = Oscillator(waveform: .sine)
    private var modulationEnvelope = ADSR()

    /// Tremolo as a rotating unit vector, so the wobble costs two multiplies
    /// rather than a sine.
    private var tremoloSine = 0.0
    private var tremoloCosine = 1.0
    private var tremoloStepSine = 0.0
    private var tremoloStepCosine = 1.0
    private var tremoloTurns = 0

    /// The per-note filter sweep: where it is, where it is going, and how
    /// far it moves each sample. Recomputing coefficients every sample would
    /// cost more than the note; every 64 is inaudible.
    private var filterFrequency = 20_000.0
    private var filterStep = 0.0
    private var filterRemaining = 0
    private var sinceFilterUpdate = 0
    private static let filterUpdateInterval = 64
    /// The 303's sweep is retuned four times as often: its attack can be two
    /// milliseconds, and at sixty-four samples that would be one update.
    private static let sweepUpdateInterval = 16

    // The metal stack, written out rather than held in an array so nothing
    // in the render loop can allocate.
    private var metal0 = Oscillator(waveform: .square)
    private var metal1 = Oscillator(waveform: .square)
    private var metal2 = Oscillator(waveform: .square)
    private var metal3 = Oscillator(waveform: .square)
    private var metal4 = Oscillator(waveform: .square)
    private var metal5 = Oscillator(waveform: .square)
    private var metalModulator = Oscillator(waveform: .square)

    private var sampleRate = 48_000.0
    private var age = 0
    private var lifetime = 0
    private var tunedFrequency = 440.0

    public init() {}

    /// Give the slot its buffers at the rate it will run at. Called once,
    /// before any audio, so that starting a note later costs nothing.
    public mutating func prepare(sampleRate: Double) {
        self.sampleRate = sampleRate
        pluck = Pluck(sampleRate: sampleRate)
    }

    public mutating func start(_ recipe: VoiceRecipe, sampleRate: Double) {
        self.recipe = recipe
        self.sampleRate = sampleRate
        preset = recipe.preset

        tunedFrequency = recipe.frequency * pow(2, recipe.detuneCents / 1200)

        amp = ADSR(
            attack: recipe.attack,
            decay: recipe.decay,
            sustain: recipe.sustain,
            release: recipe.release)
        amp.trigger(duration: recipe.duration, sampleRate: sampleRate)

        pitch = PitchEnvelope(octaves: recipe.pitchOctaves, decay: recipe.pitchDecay)
        pitch.prepare(sampleRate: sampleRate)

        filterFrequency = recipe.filterFrequency
        if recipe.filterTarget > 0 && recipe.filterRamp > 0 {
            filterRemaining = max(1, Int(recipe.filterRamp * sampleRate))
            filterStep = (recipe.filterTarget - filterFrequency) / Double(filterRemaining)
        } else {
            filterRemaining = 0
            filterStep = 0
        }
        if recipe.filterOctaves > 0 {
            filterEnvelope = ADSR(
                attack: recipe.filterAttack,
                decay: recipe.filterDecay,
                sustain: recipe.filterSustain,
                release: recipe.filterRelease)
            filterEnvelope.trigger(duration: recipe.duration, sampleRate: sampleRate)
            filterFrequency = recipe.filterFrequency
        }
        sinceFilterUpdate = 0
        setFilter()
        filter.reset()
        filterB.reset()

        switch recipe.source {
        case .oscillator:
            oscillator = Oscillator(waveform: recipe.waveform)
        case .noise:
            // Seeded from the note's own rolled numbers, so two claps in
            // the same bar are not the same clap.
            noise = Noise(colour: recipe.noiseColour, seed: Self.seed(for: recipe))
        case .metal:
            metal0.reset()
            metal1.reset()
            metal2.reset()
            metal3.reset()
            metal4.reset()
            metal5.reset()
            metalModulator.reset()

        case .pluck:
            pluck.start(
                frequency: tunedFrequency,
                dampening: recipe.pluckDampening,
                resonance: recipe.pluckResonance,
                attackNoise: recipe.attackNoise,
                seed: Self.seed(for: recipe))

        case .fm:
            carrier = Oscillator(waveform: .sine)
            modulator = Oscillator(waveform: recipe.modulatorWaveform)
            modulationEnvelope = ADSR(
                attack: recipe.modulationAttack,
                decay: recipe.modulationDecay,
                sustain: recipe.modulationSustain,
                release: recipe.modulationRelease)
            modulationEnvelope.trigger(duration: recipe.duration, sampleRate: sampleRate)
        }

        // Tone's tremolo starts its own LFO at zero and spreads the two
        // sides half a cycle apart, which is why the note moves across the
        // stereo field rather than only rising and falling.
        if recipe.tremoloRate > 0 {
            let step = 2 * .pi * recipe.tremoloRate / sampleRate
            tremoloStepSine = sin(step)
            tremoloStepCosine = cos(step)
            tremoloSine = 0
            tremoloCosine = 1
            tremoloTurns = 0
        }

        age = 0
        // A pluck has no amplitude envelope — the comb running down is the
        // whole decay — so the web gives it a flat time to live instead.
        lifetime =
            recipe.lifetime > 0
            ? Int(recipe.lifetime * sampleRate) + 1
            : Int(amp.lifetime(duration: recipe.duration) * sampleRate) + 1
        isActive = true
    }

    /// Something to seed a noise generator with that differs between two
    /// notes in the same bar but is the same for a given recipe.
    private static func seed(for recipe: VoiceRecipe) -> UInt32 {
        let mix =
            Int(recipe.frequency * 97) &+ Int(recipe.filterFrequency * 13)
            &+ Int(recipe.duration * 100_003) &+ Int(recipe.pluckResonance * 65_537)
        return UInt32(truncatingIfNeeded: mix)
    }

    /// Point the biquad — or both of them — at wherever the sweep has
    /// reached. Tone gives every section of a cascade the same Q, which is
    /// why a resonant 303 filter is as loud as it is.
    private mutating func setFilter() {
        // Coefficients only — the setters leave the filter's memory alone,
        // which is what lets a cutoff move without clicking.
        switch recipe.filter {
        case .none:
            return
        case .lowpass:
            filter.setLowpass(
                frequency: filterFrequency, q: recipe.filterQ, sampleRate: sampleRate)
            if recipe.filterCascaded {
                filterB.setLowpass(
                    frequency: filterFrequency, q: recipe.filterQ, sampleRate: sampleRate)
            }
        case .bandpass:
            filter.setBandpass(
                frequency: filterFrequency, q: recipe.filterQ, sampleRate: sampleRate)
        case .highpass:
            filter.setHighpass(
                frequency: filterFrequency, q: recipe.filterQ, sampleRate: sampleRate)
        }
    }

    public mutating func stop() {
        isActive = false
        age = 0
    }

    /// One frame, as a stereo pair.
    ///
    /// Almost every voice is mono and the width comes from its preset's
    /// chain — but a tremolo is spread across the two sides in antiphase,
    /// and summing that to mono would cancel it exactly. So the voice hands
    /// out both.
    public mutating func render() -> (left: Double, right: Double) {
        let value = renderMono()
        guard recipe.tremoloRate > 0 else { return (value, value) }

        // Tone's LFO runs between one and zero, so the level sits at a half
        // and the depth swings around it — a tremolo at depth zero still
        // halves what passes through it.
        let wobble = recipe.tremoloDepth * tremoloSine / 2
        advanceTremolo()
        return (value * (0.5 - wobble), value * (0.5 + wobble))
    }

    private mutating func advanceTremolo() {
        let turnedSine = tremoloSine * tremoloStepCosine + tremoloCosine * tremoloStepSine
        let turnedCosine = tremoloCosine * tremoloStepCosine - tremoloSine * tremoloStepSine
        tremoloSine = turnedSine
        tremoloCosine = turnedCosine

        // Rounding would let the vector drift off the unit circle over a
        // long note, so it is pulled back now and then.
        tremoloTurns += 1
        if tremoloTurns >= 4096 {
            tremoloTurns = 0
            let length = (tremoloSine * tremoloSine + tremoloCosine * tremoloCosine)
                .squareRoot()
            if length > 0 {
                tremoloSine /= length
                tremoloCosine /= length
            }
        }
    }

    private mutating func renderMono() -> Double {
        guard isActive else { return 0 }
        // A pluck carries no amplitude envelope — the comb winding down is
        // the whole of its decay — so only its time to live can end it.
        let plucking = recipe.source == .pluck
        if age >= lifetime || (!plucking && amp.isFinished) {
            stop()
            return 0
        }

        let level = plucking ? 1 : amp.next()
        var value: Double

        switch recipe.source {
        case .oscillator:
            let frequency =
                recipe.pitchOctaves > 0
                ? pitch.next(base: tunedFrequency)
                : tunedFrequency
            value = oscillator.render(frequency: frequency, sampleRate: sampleRate)

        case .noise:
            value = noise.next()

        case .metal:
            // Six partials, all bent by one modulator — the beating between
            // them is the whole sound.
            let modulator = metalModulator.render(
                frequency: tunedFrequency * recipe.harmonicity, sampleRate: sampleRate)
            let bend = 1 + recipe.modulationIndex / 100 * modulator
            let base = tunedFrequency * max(0.05, bend)
            value =
                metal0.render(
                    frequency: base * Self.metalRatios[0], sampleRate: sampleRate)
                + metal1.render(
                    frequency: base * Self.metalRatios[1], sampleRate: sampleRate)
                + metal2.render(
                    frequency: base * Self.metalRatios[2], sampleRate: sampleRate)
                + metal3.render(
                    frequency: base * Self.metalRatios[3], sampleRate: sampleRate)
                + metal4.render(
                    frequency: base * Self.metalRatios[4], sampleRate: sampleRate)
                + metal5.render(
                    frequency: base * Self.metalRatios[5], sampleRate: sampleRate)
            value /= Double(Self.metalRatios.count)

        case .pluck:
            value = pluck.next()

        case .fm:
            // Tone's depth is the note's own frequency times the modulation
            // index, opened and shut by the modulator's envelope — so the
            // bell rings at the attack and the body is left behind.
            let depth = tunedFrequency * recipe.modulationIndex * modulationEnvelope.next()
            let bend = modulator.render(
                frequency: tunedFrequency * recipe.harmonicity, sampleRate: sampleRate)
            value = carrier.renderSigned(
                frequency: tunedFrequency + depth * bend, sampleRate: sampleRate)
        }

        if recipe.filter != .none {
            if recipe.filterOctaves > 0 {
                // The 303's sweep. Tone scales the envelope linearly between
                // the base and `octaves` above it, through a square — so a
                // squared envelope, not an exponential one.
                let shape = filterEnvelope.next()
                sinceFilterUpdate += 1
                if sinceFilterUpdate >= Self.sweepUpdateInterval {
                    sinceFilterUpdate = 0
                    let reach = pow(2, recipe.filterOctaves) - 1
                    filterFrequency = recipe.filterFrequency * (1 + reach * shape * shape)
                    setFilter()
                }
            } else if filterRemaining > 0 {
                // A plain ramp, moving a little every sample and retuned
                // every sixty-fourth of them.
                filterFrequency += filterStep
                filterRemaining -= 1
                sinceFilterUpdate += 1
                if sinceFilterUpdate >= Self.filterUpdateInterval || filterRemaining == 0 {
                    sinceFilterUpdate = 0
                    setFilter()
                }
            }
            value = filter.process(value)
            if recipe.filterCascaded { value = filterB.process(value) }
        }

        age += 1
        return value * level * recipe.gain
    }
}
