// What passes from the transport to the renderer.
//
// Everything is decided before it crosses: a note arrives as a finished
// recipe and a bar's drift as finished targets, so the render thread has
// nothing to roll, look up or allocate — only a frame to wait for.

/// One instruction, timed to an absolute frame on the engine's clock.
public struct AudioEvent: Sendable {
    public enum Kind: UInt8, Sendable {
        case synthNote
        /// A preset's chain wandering somewhere new for the coming bar.
        case presetDrift
        /// Drop every sounding voice — used when the graph restarts.
        case silence
        /// The shared room, moved while it is sounding.
        case room
        /// One preset's chain, likewise.
        case chain
        /// Where the steps fall, for the effects that keep time.
        case grid
        /// A note for one of the Lab's sounds.
        case soundNote
    }

    public var kind: Kind
    /// When it happens, in frames since the renderer started.
    public var frame: Int64
    public var recipe: VoiceRecipe
    public var drift: PresetDrift
    public var room: RoomSettings
    public var chain: ChainSettings
    public var grid: StepGrid
    public var sound: SoundNote

    public init(
        kind: Kind,
        frame: Int64,
        recipe: VoiceRecipe = VoiceRecipe(),
        drift: PresetDrift = PresetDrift(),
        room: RoomSettings = RoomSettings(),
        chain: ChainSettings = ChainSettings(),
        grid: StepGrid = StepGrid(),
        sound: SoundNote = SoundNote()
    ) {
        self.kind = kind
        self.frame = frame
        self.recipe = recipe
        self.drift = drift
        self.room = room
        self.chain = chain
        self.grid = grid
        self.sound = sound
    }

    public static func note(_ recipe: VoiceRecipe, at frame: Int64) -> AudioEvent {
        AudioEvent(kind: .synthNote, frame: frame, recipe: recipe)
    }

    public static func sound(_ note: SoundNote, at frame: Int64) -> AudioEvent {
        AudioEvent(kind: .soundNote, frame: frame, sound: note)
    }

    public static func drift(_ drift: PresetDrift, at frame: Int64) -> AudioEvent {
        AudioEvent(kind: .presetDrift, frame: frame, drift: drift)
    }

    public static func room(_ room: RoomSettings) -> AudioEvent {
        AudioEvent(kind: .room, frame: 0, room: room)
    }

    public static func chain(_ chain: ChainSettings) -> AudioEvent {
        AudioEvent(kind: .chain, frame: 0, chain: chain)
    }

    /// Applied as soon as it is reached rather than at its frame: the grid
    /// names its own frame, and waiting for it would be a step late.
    public static func grid(_ grid: StepGrid) -> AudioEvent {
        AudioEvent(kind: .grid, frame: 0, grid: grid)
    }
}

/// The shared room's three numbers, small enough to cross the queue by value.
public struct RoomSettings: Sendable, Equatable {
    public var decay: Double
    public var preDelay: Double
    public var damping: Double

    public init(
        decay: Double = Reverb.defaultDecay,
        preDelay: Double = Reverb.defaultPreDelay,
        damping: Double = Reverb.damping
    ) {
        self.decay = decay
        self.preDelay = preDelay
        self.damping = damping
    }

    /// What the panel currently asks for.
    public init(_ tuning: Tuning) {
        self.init(
            decay: tuning[.reverbDecay].lower,
            preDelay: tuning[.reverbPreDelay].lower,
            damping: tuning[.reverbDamping].lower)
    }
}

/// What a preset's chain can be told while it is running.
public struct ChainSettings: Sendable, Equatable {
    public var preset: SynthPreset
    /// Where the reverb send is rolled off from below.
    public var sendHighpass: Double
    /// How much of the chain the echo repeats. Negative leaves it alone.
    public var delayWet: Double

    public init(
        preset: SynthPreset = .reverie,
        sendHighpass: Double = 200,
        delayWet: Double = -1
    ) {
        self.preset = preset
        self.sendHighpass = sendHighpass
        self.delayWet = delayWet
    }
}

/// A note for a Lab sound: which sound, and what to play on it. Its timbre
/// is rolled inside the synth, so this is all that has to cross.
public struct SoundNote: Sendable, Equatable {
    /// The sound's id — its voice index.
    public var sound: Int
    public var midi: Int
    public var velocity: Double
    /// How long the key is held.
    public var seconds: Double

    public init(sound: Int = 0, midi: Int = 60, velocity: Double = 1, seconds: Double = 0.1) {
        self.sound = sound
        self.midi = midi
        self.velocity = velocity
        self.seconds = seconds
    }
}
