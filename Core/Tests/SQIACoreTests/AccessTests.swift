// What the subscription opens, and what it leaves alone.

import Testing

@testable import SQIACore

@Suite("Access")
struct AccessTests {
    @Test("The first track is free, the second is Plus")
    func secondTrackIsPlus() {
        #expect(Access.free.opens(track: 0))
        #expect(!Access.free.opens(track: 1))
        #expect(Access.plus.opens(track: 0))
        #expect(Access.plus.opens(track: 1))
    }

    @Test("Every track the sequencer has is covered")
    func everyTrackIsAnswered() {
        let opened = (0..<SequencerState.trackCount).filter { Access.free.opens(track: $0) }
        #expect(opened == [0])
        #expect((0..<SequencerState.trackCount).allSatisfy { Access.plus.opens(track: $0) })
    }

    @Test("A locked track is silent, whatever its mute says")
    func lockedTrackIsSilent() {
        #expect(!Access.free.sounds(track: 1, muted: false))
        #expect(!Access.free.sounds(track: 1, muted: true))
        #expect(Access.free.sounds(track: 0, muted: false))
        #expect(!Access.free.sounds(track: 0, muted: true))
        #expect(Access.plus.sounds(track: 1, muted: false))
        #expect(!Access.plus.sounds(track: 1, muted: true))
    }

    @Test("Plus allows every feature, free allows none")
    func features() {
        for feature in PlusFeature.allCases {
            #expect(Access.plus.allows(feature))
            #expect(!Access.free.allows(feature))
        }
    }
}
