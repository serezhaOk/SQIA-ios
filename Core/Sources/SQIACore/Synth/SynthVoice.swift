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
    private var oscillator = Oscillator()
    private var noise = Noise()
    /// Built once per slot, because its delay line is the only thing in a
    /// voice that allocates and the render thread must never do that.
    private var pluck = Pluck(sampleRate: 48_000)

    /// The per-note filter sweep: where it is, where it is going, and how
    /// far it moves each sample. Recomputing coefficients every sample would
    /// cost more than the note; every 64 is inaudible.
    private var filterFrequency = 20_000.0
    private var filterStep = 0.0
    private var filterRemaining = 0
    private var sinceFilterUpdate = 0
    private static let filterUpdateInterval = 64

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
        sinceFilterUpdate = 0
        setFilter()
        filter.reset()

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

    /// Point the biquad at wherever the sweep has reached.
    private mutating func setFilter() {
        switch recipe.filter {
        case .none:
            break
        case .lowpass:
            filter.setLowpass(
                frequency: filterFrequency, q: recipe.filterQ, sampleRate: sampleRate)
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

    public mutating func render() -> Double {
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
        }

        if recipe.filter != .none {
            // A sweeping filter moves a little every sample and is retuned
            // every sixty-fourth of them.
            if filterRemaining > 0 {
                filterFrequency += filterStep
                filterRemaining -= 1
                sinceFilterUpdate += 1
                if sinceFilterUpdate >= Self.filterUpdateInterval || filterRemaining == 0 {
                    sinceFilterUpdate = 0
                    setFilter()
                }
            }
            value = filter.process(value)
        }

        age += 1
        return value * level * recipe.gain
    }
}
