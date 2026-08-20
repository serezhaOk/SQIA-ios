// The session as data: the key, the tracks, and the round trip through a
// saved project — which is the part that has to hold, because the same rows
// are read and written by the web.

import Testing

@testable import SQIACore

@Suite("Sequencer state")
struct SequencerStateTests {
    private func fresh() -> SequencerState {
        SequencerState.fresh(voices: [0, 4])
    }

    @Test("A new session starts where the web starts")
    func defaults() {
        let state = fresh()
        #expect(state.bpm == 120)
        #expect(state.rootName == "A")
        #expect(state.scale.name == "minor")
        #expect(state.tracks.count == 2)
        #expect(state.activeTrackIndex == 0)
        #expect(state.tracks.allSatisfy { !$0.muted })
        #expect(state.tracks.allSatisfy { !$0.grid.hasNotes })
        // Tracks start on different voices so the mixer is useful at once.
        #expect(state.tracks[0].voiceIndex != state.tracks[1].voiceIndex)
    }

    @Test("The root walks the twelve notes and comes back")
    func rootCycles() {
        var state = fresh()
        var seen: [String] = []
        for _ in 0..<12 {
            seen.append(state.rootName)
            state.cycleRoot()
        }
        #expect(seen == ["A", "A#", "B", "C", "C#", "D", "D#", "E", "F", "F#", "G", "G#"])
        #expect(state.rootName == "A")
    }

    @Test("The scale cycles through all five and comes back")
    func scaleCycles() {
        var state = fresh()
        var seen: [String] = []
        for _ in 0..<Music.scales.count {
            seen.append(state.scale.name)
            state.cycleScale()
        }
        #expect(seen == ["minor", "major", "dorian", "penta", "phrygian"])
        #expect(state.scale.name == "minor")
    }

    @Test("The key moves the pitches, not the pattern")
    func keyMovesPitches() {
        var state = fresh()
        state.brush(gx: 3.5, gy: 5.5)
        let pattern = state.activeTrack.grid

        let before = state.midiTable
        state.cycleRoot()
        let after = state.midiTable

        #expect(after == before.map { $0 + 1 })
        #expect(state.activeTrack.grid == pattern)
    }

    /// The picker sets the key outright. Cycling to it and choosing it have
    /// to land in the same place, and nothing out of range may move it.
    @Test("Choosing a key lands where cycling to it would")
    func keyCanBeSetOutright() {
        var chosen = fresh()
        var cycled = fresh()

        // However far it happens to be from where a fresh session starts.
        let steps = (7 - chosen.rootPc + 12) % 12
        chosen.setRoot(7)
        for _ in 0..<steps { cycled.cycleRoot() }
        #expect(chosen.rootPc == cycled.rootPc)
        #expect(chosen.midiTable == cycled.midiTable)

        let scaleSteps = (3 - chosen.scaleIndex + 5) % 5
        chosen.setScale(3)
        for _ in 0..<scaleSteps { cycled.cycleScale() }
        #expect(chosen.scale == cycled.scale)

        // Out of range is ignored rather than clamped: a picker cannot ask
        // for one, and silently landing somewhere else would be worse.
        chosen.setRoot(-1)
        chosen.setRoot(99)
        chosen.setScale(99)
        #expect(chosen.rootPc == 7)
        #expect(chosen.scaleIndex == 3)
    }

    @Test("A pattern survives the key being chosen")
    func choosingAKeyKeepsThePattern() {
        var state = fresh()
        state.brush(gx: 3.5, gy: 5.5)
        let pattern = state.activeTrack.grid
        state.setRoot(9)
        state.setScale(2)
        #expect(state.activeTrack.grid == pattern)
    }

    @Test("Drawing only touches the active track")
    func editsGoToTheActiveTrack() {
        var state = fresh()
        state.brush(gx: 3.5, gy: 5.5)
        #expect(state.tracks[0].grid.hasNotes)
        #expect(!state.tracks[1].grid.hasNotes)

        state.selectTrack(1)
        state.randomize(using: Mulberry32(seed: 1))
        #expect(state.tracks[1].grid.hasNotes)
        // And the first track keeps what it had.
        #expect(state.tracks[0].grid.at(row: 5, column: 3) == 1)
    }

    @Test("Selecting a track that is not there changes nothing")
    func selectionIsGuarded() {
        var state = fresh()
        state.selectTrack(9)
        #expect(state.activeTrackIndex == 0)
        state.selectTrack(-1)
        #expect(state.activeTrackIndex == 0)
    }

    @Test("Cycling walks the tracks in a ring")
    func trackCycles() {
        var state = fresh()
        state.cycleTrack()
        #expect(state.activeTrackIndex == 1)
        state.cycleTrack()
        #expect(state.activeTrackIndex == 0)
    }

    @Test("Muting toggles one track and leaves the other alone")
    func muting() {
        var state = fresh()
        state.toggleMute(1)
        #expect(!state.tracks[0].muted)
        #expect(state.tracks[1].muted)
        state.toggleMute(1)
        #expect(!state.tracks[1].muted)
    }

    /// The round trip is the whole reason the format is shared with the web.
    @Test("A session survives being saved and loaded")
    func roundTrip() {
        var state = fresh()
        state.bpm = 137
        state.cycleRoot()
        state.cycleScale()
        state.randomize(using: Mulberry32(seed: 7))
        state.selectTrack(1)
        state.randomize(using: Mulberry32(seed: 8))
        state.toggleMute(1)

        var restored = fresh()
        restored.apply(state.snapshot())

        #expect(restored.bpm == 137)
        #expect(restored.rootPc == state.rootPc)
        #expect(restored.scale.name == state.scale.name)
        #expect(restored.tracks.map(\.muted) == state.tracks.map(\.muted))
        #expect(restored.tracks.map(\.voiceIndex) == state.tracks.map(\.voiceIndex))
        // Opening a project always lands on the first track.
        #expect(restored.activeTrackIndex == 0)

        // Cells are stored to two decimals, so what has to survive is which
        // ones hold notes and roughly how bright.
        for (a, b) in zip(state.tracks, restored.tracks) {
            for i in 0..<NoteGrid.count {
                #expect((a.grid.cells[i] > 0) == (b.grid.cells[i] > 0))
                #expect(abs(Double(a.grid.cells[i]) - Double(b.grid.cells[i])) <= 0.005)
            }
        }
    }

    @Test("An unfamiliar scale name falls back to minor rather than failing")
    func unknownScale() {
        var state = fresh()
        state.apply(
            ProjectSnapshot(bpm: 90, rootPc: 3, scale: "lydian-dominant", tracks: []))
        #expect(state.scale.name == "minor")
        #expect(state.rootPc == 3)
        #expect(state.bpm == 90)
    }

    @Test("A project with fewer tracks leaves the rest as they were")
    func shortProject() {
        var state = fresh()
        state.selectTrack(1)
        state.randomize(using: Mulberry32(seed: 3))
        let untouched = state.tracks[1].grid

        state.apply(
            ProjectSnapshot(
                bpm: 100, rootPc: 0, scale: "major",
                tracks: [TrackSnapshot(voiceIdx: 2, muted: false, cells: [1, 0.5])]))

        #expect(state.tracks[0].voiceIndex == 2)
        #expect(state.tracks[0].grid.at(row: 0, column: 0) == 1)
        #expect(state.tracks[1].grid == untouched)
    }

    @Test("Tempo is stored as the whole number the column holds")
    func tempoRounds() {
        var state = fresh()
        state.bpm = 137.6
        #expect(state.snapshot().bpm == 138)
    }
}
