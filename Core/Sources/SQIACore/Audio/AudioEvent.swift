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
    }

    public var kind: Kind
    /// When it happens, in frames since the renderer started.
    public var frame: Int64
    public var recipe: VoiceRecipe
    public var drift: PresetDrift
    public var room: RoomSettings

    public init(
        kind: Kind,
        frame: Int64,
        recipe: VoiceRecipe = VoiceRecipe(),
        drift: PresetDrift = PresetDrift(),
        room: RoomSettings = RoomSettings()
    ) {
        self.kind = kind
        self.frame = frame
        self.recipe = recipe
        self.drift = drift
        self.room = room
    }

    public static func note(_ recipe: VoiceRecipe, at frame: Int64) -> AudioEvent {
        AudioEvent(kind: .synthNote, frame: frame, recipe: recipe)
    }

    public static func drift(_ drift: PresetDrift, at frame: Int64) -> AudioEvent {
        AudioEvent(kind: .presetDrift, frame: frame, drift: drift)
    }

    public static func room(_ room: RoomSettings) -> AudioEvent {
        AudioEvent(kind: .room, frame: 0, room: room)
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
