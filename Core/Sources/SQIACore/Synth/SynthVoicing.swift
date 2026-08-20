// Rolling a note.
//
// Direct port of the preset methods in the web app's src/synths.ts, down to
// the order the random draws happen in: a note takes its values from the
// stream in exactly the sequence the web takes them, so a seeded run can be
// compared at all.
//
// A single note can turn into several voices — an octave ghost a moment
// later, a snare's body underneath it, a clap's four slaps — so this returns
// a list, each with its own offset from the step.

import Foundation

public struct ScheduledVoice: Sendable, Equatable {
    public var recipe: VoiceRecipe
    /// Seconds after the step's own time.
    public var offset: Double

    public init(recipe: VoiceRecipe, offset: Double = 0) {
        self.recipe = recipe
        self.offset = offset
    }
}

public enum SynthVoicing {
    /// REVERIE's longest tail; a note's release is 10–90% of it.
    public static let maxRelease = 3.2

    public static func notes(
        preset: SynthPreset,
        midi: Int,
        velocity: Double,
        using random: RandomSource
    ) -> [ScheduledVoice] {
        switch preset {
        case .reverie:
            return reverie(midi: midi, velocity: velocity, using: random)
        case .machine:
            return machine(midi: midi, velocity: velocity, using: random)
        case .kalimba:
            return kalimba(midi: midi, velocity: velocity, using: random)
        case .rhodes:
            return rhodes(midi: midi, velocity: velocity, using: random)
        case .acid:
            return acid(midi: midi, velocity: velocity, using: random)
        }
    }

    /// Velocity as Tone's PluckSynth has to take it.
    ///
    /// A PluckSynth has no velocity argument — it is excited by noise, not
    /// by an envelope — so the web puts the dynamics in the voice's level
    /// instead, with a floor so a soft cell never disappears entirely.
    private static func pluckDecibels(_ velocity: Double) -> Double {
        max(-40, 20 * log10(max(0.02, velocity)))
    }

    // ------------------------------------------------------------ REVERIE --
    // Oscillator flavour re-rolled per note, random 10–90% release, ghost
    // octave sparkles and the occasional sub for weight.

    private static func reverieNote(
        frequency: Double,
        duration: Double,
        velocity: Double,
        release: Double,
        using random: RandomSource
    ) -> VoiceRecipe {
        var recipe = VoiceRecipe()
        recipe.preset = .reverie
        recipe.source = .oscillator
        recipe.frequency = frequency
        recipe.duration = duration
        recipe.gain = VoiceRecipe.gain(db: -12, velocity: velocity)

        recipe.waveform = random.pick(Waveform.reverieChoices)
        // Three notes in ten come in slowly, which is what makes it a pad
        // rather than a keyboard.
        recipe.attack =
            random.chance(0.3) ? random.value(0.04, 0.35) : random.value(0.004, 0.02)
        recipe.decay = random.value(0.08, 0.5)
        recipe.sustain = random.value(0.1, 0.5)
        recipe.release = release
        recipe.detuneCents = random.value(-14, 14)
        return recipe
    }

    private static func reverie(
        midi: Int,
        velocity: Double,
        using random: RandomSource
    ) -> [ScheduledVoice] {
        let frequency = Music.frequency(ofMidi: midi)
        let duration = random.value(0.06, 0.3)
        let release = random.value(0.1, 0.9) * maxRelease

        var voices = [
            ScheduledVoice(
                recipe: reverieNote(
                    frequency: frequency, duration: duration, velocity: velocity,
                    release: release, using: random))
        ]

        if random.chance(0.22) {
            let offset = random.value(0.02, 0.09)
            let ghostVelocity = velocity * random.value(0.2, 0.45)
            voices.append(
                ScheduledVoice(
                    recipe: reverieNote(
                        frequency: frequency * 2, duration: duration * 0.6,
                        velocity: ghostVelocity, release: release * 0.7, using: random),
                    offset: offset))
        }

        if random.chance(0.1) {
            voices.append(
                ScheduledVoice(
                    recipe: reverieNote(
                        frequency: frequency / 2, duration: duration,
                        velocity: velocity * 0.5, release: release, using: random)))
        }
        return voices
    }

    // ------------------------------------------------------------ KALIMBA --
    // A muted wooden thumb-piano. How long the tine rings and how bright it
    // arrives are rolled per note, and a lowpass over the top sweeps down as
    // it decays, which is what keeps it wooden rather than harp-like.

    private static func kalimba(
        midi: Int,
        velocity: Double,
        using random: RandomSource
    ) -> [ScheduledVoice] {
        let frequency = Music.frequency(ofMidi: midi)

        let resonance = random.value(0.55, 0.94)  // how long the tine rings
        let dampening = random.value(900, 4500)  // the pluck's cutoff

        var recipe = VoiceRecipe()
        recipe.preset = .kalimba
        recipe.source = .pluck
        recipe.frequency = frequency
        recipe.gain = VoiceRecipe.gain(db: 5 + pluckDecibels(velocity))
        recipe.pluckResonance = resonance
        recipe.pluckDampening = dampening
        recipe.attackNoise = random.value(0.4, 1.8)
        // Tone's PluckSynth takes a release, and the web never triggers one
        // — but the value still comes off the stream, so it comes off this
        // one too.
        _ = random.value(0.1, 0.9)
        recipe.lifetime = 2.2

        recipe.filter = .lowpass
        recipe.filterFrequency = random.value(1200, 5200)
        recipe.filterQ = random.value(0.3, 2.2)
        recipe.filterTarget = random.value(500, 1600)
        recipe.filterRamp = random.value(0.3, 1.1)

        var voices = [ScheduledVoice(recipe: recipe)]

        // Soft octave ghost, like a thumb catching the neighbouring tine.
        // It goes straight to the chain, with no lowpass of its own.
        if random.chance(0.18) {
            var ghost = VoiceRecipe()
            ghost.preset = .kalimba
            ghost.source = .pluck
            ghost.frequency = frequency * 2
            ghost.gain = VoiceRecipe.gain(db: -3 + pluckDecibels(velocity * 0.5))
            ghost.attackNoise = 0.6
            ghost.pluckDampening = dampening * 1.4
            ghost.pluckResonance = resonance * 0.8
            ghost.lifetime = 1.6
            voices.append(
                ScheduledVoice(recipe: ghost, offset: random.value(0.01, 0.05)))
        }
        return voices
    }

    // --------------------------------------------------------------- ACID --
    // A 303 in spirit: one blade through a steep resonant lowpass that an
    // envelope sweeps on every note. Two octaves below the grid, so it sits
    // under the other tracks as a bass.
    //
    // Resonance and cutoff are where the character lives, so they are what
    // gets rolled. A loud cell is an accent, and an accent pushes the filter
    // as well as the amplitude — which is what the accent line on a real 303
    // does.

    /// Above this a cell counts as an accent.
    public static let acidAccent = 0.7

    private static func acid(
        midi: Int,
        velocity: Double,
        using random: RandomSource
    ) -> [ScheduledVoice] {
        let frequency = Music.frequency(ofMidi: midi)
        let accent = velocity > acidAccent

        // How resonant the filter is. High Q with a low base is the squelch.
        let q = accent ? random.value(9, 15) : random.value(4, 11)
        // Where the sweep starts, and how many octaves it climbs.
        let base = random.value(90, 260) * (accent ? random.value(1.1, 1.6) : 1)
        let octaves = accent ? random.value(3, 4.6) : random.value(1.6, 3.4)
        // How fast it falls back — short is a blip, long is a wow.
        let sweep = random.value(0.09, 0.42)
        let duration = random.value(0.06, 0.22)
        let release = random.value(0.03, 0.14)

        var recipe = VoiceRecipe()
        recipe.preset = .acid
        recipe.source = .oscillator
        // Bass carries far more energy than the other voices at the same
        // nominal level, so it sits deliberately under them.
        recipe.gain = VoiceRecipe.gain(
            db: -18, velocity: accent ? 1 : velocity * 0.85)
        recipe.frequency = frequency / 4
        recipe.duration = duration

        recipe.waveform = random.pick([Waveform.sawtooth, .square])
        recipe.filter = .lowpass
        recipe.filterCascaded = true
        recipe.filterQ = q
        recipe.attack = 0.002
        recipe.decay = random.value(0.05, 0.3)
        recipe.sustain = accent ? random.value(0.25, 0.5) : random.value(0.05, 0.25)
        recipe.release = release

        recipe.filterAttack = random.value(0.002, 0.014)
        recipe.filterDecay = sweep
        recipe.filterSustain = random.value(0.02, 0.22)
        recipe.filterRelease = random.value(0.05, 0.25)
        recipe.filterFrequency = base
        recipe.filterOctaves = octaves
        recipe.detuneCents = random.value(-6, 6)

        recipe.lifetime = duration + release + 0.5
        return [ScheduledVoice(recipe: recipe)]
    }

    // ------------------------------------------------------------- RHODES --
    // An FM electric piano: a bell-ish attack over a warm body, with a slow
    // tremolo so held notes keep moving. The bell is the modulator's own
    // envelope opening and shutting faster than the note it sits on.

    /// The harmonicities the web draws from. 3.01 is not a typo — a ratio a
    /// hair off a whole number is what makes a tine beat rather than ring.
    static let rhodesHarmonicities = [1.0, 2, 3, 3.01, 4]

    private static func rhodes(
        midi: Int,
        velocity: Double,
        using random: RandomSource
    ) -> [ScheduledVoice] {
        let frequency = Music.frequency(ofMidi: midi)
        let duration = random.value(0.12, 0.45)
        let release = random.value(0.4, 1.8)

        var recipe = VoiceRecipe()
        recipe.preset = .rhodes
        recipe.source = .fm
        recipe.frequency = frequency
        recipe.duration = duration
        recipe.gain = VoiceRecipe.gain(db: 0, velocity: velocity)

        recipe.harmonicity = random.pick(rhodesHarmonicities)
        recipe.modulationIndex = random.value(3, 11)
        recipe.attack = random.value(0.002, 0.012)
        recipe.decay = random.value(0.25, 0.9)
        recipe.sustain = random.value(0.05, 0.28)
        recipe.release = release
        recipe.modulatorWaveform = random.pick([Waveform.sine, .triangle])
        recipe.modulationAttack = random.value(0.002, 0.02)
        recipe.modulationDecay = random.value(0.1, 0.5)
        recipe.modulationSustain = random.value(0, 0.2)
        recipe.modulationRelease = random.value(0.2, 0.8)
        recipe.detuneCents = random.value(-8, 8)

        recipe.tremoloRate = random.value(2.5, 7)
        recipe.tremoloDepth = random.value(0.15, 0.55)
        recipe.lifetime = duration + release + 0.4

        var voices = [ScheduledVoice(recipe: recipe)]

        // Occasional fifth or octave, the way a Rhodes bar rings
        // sympathetically. No tremolo on this one.
        if random.chance(0.16) {
            var ghost = VoiceRecipe()
            ghost.preset = .rhodes
            ghost.source = .fm
            ghost.harmonicity = random.pick([2.0, 3])
            ghost.modulationIndex = random.value(2, 6)
            ghost.attack = 0.005
            ghost.decay = 0.4
            ghost.sustain = 0.05
            ghost.release = 0.9
            ghost.frequency = frequency * random.pick([1.5, 2.0])
            ghost.duration = duration * 0.7
            ghost.gain = VoiceRecipe.gain(db: -12, velocity: velocity * 0.4)
            ghost.lifetime = duration + 1.4
            voices.append(
                ScheduledVoice(recipe: ghost, offset: random.value(0.01, 0.06)))
        }
        return voices
    }

    // ------------------------------------------------------------ MACHINE --
    // The column's register picks the instrument — low columns are kicks and
    // toms, the middle is snare and clap, the top is metal — and the exact
    // pitch tunes it, so drawing melodies draws grooves.

    private static func machine(
        midi: Int,
        velocity: Double,
        using random: RandomSource
    ) -> [ScheduledVoice] {
        let frequency = Music.frequency(ofMidi: midi)
        let kind = ((midi % 12) + 12) % 12

        if kind < 3 { return [kick(frequency, velocity, random)] }
        if kind < 6 { return [tom(frequency, velocity, random)] }
        if kind < 9 { return snare(frequency, velocity, random) }
        if kind < 11 { return clap(velocity, random) }
        return [metal(frequency, velocity, random)]
    }

    private static func kick(
        _ frequency: Double, _ velocity: Double, _ random: RandomSource
    ) -> ScheduledVoice {
        var recipe = VoiceRecipe()
        recipe.preset = .machine
        recipe.source = .oscillator
        recipe.frequency = frequency / 4
        recipe.gain = VoiceRecipe.gain(db: -3, velocity: velocity)
        recipe.pitchDecay = random.value(0.02, 0.09)
        recipe.pitchOctaves = random.value(3, 8)
        recipe.waveform = random.pick([Waveform.sine, .triangle])
        recipe.attack = 0.001
        recipe.decay = random.value(0.18, 0.6)
        recipe.sustain = 0
        recipe.release = random.value(0.05, 0.3)
        recipe.duration = random.value(0.08, 0.3)
        return ScheduledVoice(recipe: recipe)
    }

    private static func tom(
        _ frequency: Double, _ velocity: Double, _ random: RandomSource
    ) -> ScheduledVoice {
        var recipe = VoiceRecipe()
        recipe.preset = .machine
        recipe.source = .oscillator
        recipe.frequency = frequency / 2
        recipe.gain = VoiceRecipe.gain(db: -7, velocity: velocity)
        recipe.pitchDecay = random.value(0.04, 0.14)
        recipe.pitchOctaves = random.value(1.5, 4)
        recipe.waveform = .sine
        recipe.attack = 0.001
        recipe.decay = random.value(0.12, 0.45)
        recipe.sustain = 0
        recipe.release = random.value(0.05, 0.2)
        recipe.duration = random.value(0.06, 0.24)
        return ScheduledVoice(recipe: recipe)
    }

    /// Noise burst plus a tuned body, which is what a snare is.
    private static func snare(
        _ frequency: Double, _ velocity: Double, _ random: RandomSource
    ) -> [ScheduledVoice] {
        var burst = VoiceRecipe()
        burst.preset = .machine
        burst.source = .noise
        burst.frequency = frequency
        burst.gain = VoiceRecipe.gain(db: -9, velocity: velocity)
        burst.noiseColour = random.pick([NoiseColour.white, .pink])
        burst.attack = 0.001
        burst.decay = random.value(0.08, 0.3)
        burst.sustain = 0
        burst.release = random.value(0.02, 0.12)
        burst.filter = .bandpass
        burst.filterFrequency = random.value(1200, 3600)
        burst.filterQ = random.value(0.6, 2.4)
        burst.duration = random.value(0.05, 0.2)

        var body = VoiceRecipe()
        body.preset = .machine
        body.source = .oscillator
        body.frequency = frequency / 2
        body.gain = VoiceRecipe.gain(db: -15, velocity: velocity * 0.7)
        body.waveform = .sine
        body.pitchDecay = 0.03
        body.pitchOctaves = 2
        body.attack = 0.001
        body.decay = 0.12
        body.sustain = 0
        body.release = 0.05
        body.duration = 0.06

        return [ScheduledVoice(recipe: burst), ScheduledVoice(recipe: body)]
    }

    /// A few noise slaps in quick succession.
    private static func clap(
        _ velocity: Double, _ random: RandomSource
    ) -> [ScheduledVoice] {
        let hits = 2 + random.index(3)
        var voices: [ScheduledVoice] = []
        voices.reserveCapacity(hits)

        for i in 0..<hits {
            var recipe = VoiceRecipe()
            recipe.preset = .machine
            recipe.source = .noise
            recipe.frequency = 1000
            recipe.gain = VoiceRecipe.gain(db: -13, velocity: velocity * 0.8)
            recipe.noiseColour = .white
            recipe.attack = 0.001
            recipe.decay = random.value(0.03, 0.12)
            recipe.sustain = 0
            recipe.release = 0.02
            recipe.filter = .bandpass
            recipe.filterFrequency = random.value(900, 2200)
            recipe.filterQ = random.value(1, 3)
            recipe.duration = 0.03
            voices.append(
                ScheduledVoice(
                    recipe: recipe, offset: Double(i) * random.value(0.008, 0.02)))
        }
        return voices
    }

    /// Hats and cymbals, open or closed at random.
    private static func metal(
        _ frequency: Double, _ velocity: Double, _ random: RandomSource
    ) -> ScheduledVoice {
        let open = random.chance(0.25)

        var recipe = VoiceRecipe()
        recipe.preset = .machine
        recipe.source = .metal
        recipe.gain = VoiceRecipe.gain(db: -21, velocity: velocity)
        recipe.attack = 0.001
        recipe.decay = open ? random.value(0.3, 0.9) : random.value(0.03, 0.14)
        recipe.sustain = 0
        recipe.release = random.value(0.02, 0.2)
        recipe.harmonicity = random.value(3, 9)
        recipe.modulationIndex = random.value(12, 42)
        recipe.resonance = random.value(2000, 7000)
        _ = random.value(0.5, 2)  // Tone's `octaves`, which drives a filter envelope we do not model
        recipe.frequency = frequency * random.value(0.9, 1.6)
        recipe.duration = open ? random.value(0.2, 0.6) : random.value(0.02, 0.1)
        recipe.filter = .highpass
        recipe.filterFrequency = recipe.resonance
        recipe.filterQ = 1
        return ScheduledVoice(recipe: recipe)
    }

    // -------------------------------------------------------------- drift --

    /// One bar's worth of wandering for a preset's chain.
    ///
    /// `division` is the subdivision the echo currently sits on; zero means
    /// it has never been set, which always forces a fresh roll.
    public static func drift(
        preset: SynthPreset,
        bpm: Double,
        division: Int,
        using random: RandomSource
    ) -> PresetDrift {
        let settings = PresetSettings.of(preset)
        var drift = PresetDrift()
        drift.preset = preset
        drift.cutoff = random.value(
            settings.cutoff.lowerBound, settings.cutoff.upperBound)
        drift.cutoffRamp = random.value(0.4, 2.5)
        drift.feedback = random.value(0.2, 0.55)
        drift.reverbSend = random.value(
            settings.reverbWet.lowerBound, settings.reverbWet.upperBound)

        // The web reads the current depth and nudges it; the caller passes
        // the nudge on and the chain clamps.
        drift.chorusDepthDelta = random.value(-0.09, 0.09)

        // Short-circuit on purpose: an echo that has never been set rolls
        // without spending a value, exactly as the web's `||` does.
        let reroll = division == 0 || random.chance(0.25)
        if reroll {
            let stepDuration = 60 / bpm / 4
            drift.echo = stepDuration * Double(random.pick([2, 3, 4, 6]))
        }
        return drift
    }
}
