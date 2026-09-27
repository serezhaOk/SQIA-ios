// What this phone may use: the free app, or the free app and SQIA Plus.
//
// One place that says what the subscription opens, so the screen that
// draws a padlock, the transport that decides what is heard and the mixer
// that dims a panel all ask the same question and get the same answer. A
// feature added to Plus later is a case here and a call site, not a second
// flag threaded through the app.
//
// Nothing here knows about StoreKit. The app works out whether there is a
// subscription and hands the answer in as a value.

import Foundation

public enum PlusFeature: String, CaseIterable, Sendable {
    /// The mixer's second track: opening it, drawing on it, hearing it.
    case secondTrack
    /// The pattern playing on once the app is out of sight or the phone
    /// is locked.
    case backgroundPlayback
}

public struct Access: Sendable, Equatable {
    public var hasPlus: Bool

    public init(hasPlus: Bool) {
        self.hasPlus = hasPlus
    }

    public static let free = Access(hasPlus: false)
    public static let plus = Access(hasPlus: true)

    /// A switch rather than `hasPlus` on its own, so that a feature which
    /// ever comes free — or free for a while — is one line to change.
    public func allows(_ feature: PlusFeature) -> Bool {
        switch feature {
        case .secondTrack, .backgroundPlayback: hasPlus
        }
    }

    /// The first track is everybody's. Every one after it is Plus.
    public func opens(track index: Int) -> Bool {
        index == 0 || allows(.secondTrack)
    }

    /// Whether a track is heard.
    ///
    /// A locked track keeps its notes — a project drawn with two tracks
    /// before the subscription lapsed, or in the browser, opens with both
    /// intact and plays the second again the moment Plus comes back. It is
    /// silent rather than emptied, so nothing is lost by not paying.
    public func sounds(track index: Int, muted: Bool) -> Bool {
        !muted && opens(track: index)
    }
}
