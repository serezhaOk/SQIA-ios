// How things arrive and leave.
//
// Two speeds, and the difference between them is whether anything moves. A
// fade is text or a control changing its mind in place, and 0.18 is the
// number the sequencer already settled on for that. A settle is something
// taking up or giving back room — a card leaving the grid, the rest closing
// over the gap — and gets a little longer, on a curve that does most of its
// travelling in the first third so it never feels like it is waiting.
//
// Nothing here starts from nothing. A card arrives from 96 per cent of its
// size, not from a point: things that are almost there read as having been
// there, and things that grow from zero read as a trick.

import SwiftUI

enum Motion {
    /// Opacity and colour, in place.
    static let fade = Animation.easeOut(duration: 0.18)

    /// Room being taken up or given back. A steep ease-out: the move is
    /// mostly over before the eye has caught up with it.
    static let settle = Animation.timingCurve(0.23, 1, 0.32, 1, duration: 0.32)

    /// With Reduce Motion on, room still changes hands — but at the pace of
    /// a fade, so nothing is seen to travel.
    static func settle(reduced: Bool) -> Animation {
        reduced ? fade : settle
    }

    /// A card coming into, or going out of, a grid.
    static let arrive = AnyTransition.opacity.combined(with: .scale(scale: 0.96))
}
