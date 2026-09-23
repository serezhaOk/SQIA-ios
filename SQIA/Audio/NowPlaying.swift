// The lock screen's and Control Centre's view of the app: which project is
// playing, and the play and pause buttons that reach back into it.
//
// iOS shows this for whichever app last played through a non-mixing
// `.playback` session, which is what the sequencer's session is. Without it
// the sound carries on behind the lock screen with nothing there to say
// what it is or to stop it — the one thing a person reaching for the phone
// in the dark wants to do.
//
// It knows nothing of projects or engines. `AppModel` tells it what is
// playing and hands it the two things the buttons do.

import MediaPlayer
import UIKit

@MainActor
final class NowPlaying {
    private let onPlay: () -> Bool
    private let onPause: () -> Void
    private var title: String?

    /// Each returns whether it did anything: a play with nothing to resume
    /// tells the system so, and the button stays as it was.
    init(onPlay: @escaping () -> Bool, onPause: @escaping () -> Void) {
        self.onPlay = onPlay
        self.onPause = onPause
        wireCommands()
    }

    /// What the card on the lock screen says, and whether it shows play or
    /// pause. A nil title takes the card away.
    func show(title: String?, isPlaying: Bool) {
        self.title = title
        let centre = MPNowPlayingInfoCenter.default()
        guard let title else {
            centre.nowPlayingInfo = nil
            return
        }
        centre.nowPlayingInfo = [
            MPMediaItemPropertyTitle: title,
            MPMediaItemPropertyArtist: "SQIA",
            MPMediaItemPropertyArtwork: Self.artwork,
            // A loop has no length and no position; saying so keeps the
            // system from drawing a scrubber that means nothing.
            MPNowPlayingInfoPropertyIsLiveStream: true,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
        ]
    }

    private func wireCommands() {
        let commands = MPRemoteCommandCenter.shared()
        commands.playCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.onPlay() == true ? .success : .noActionableNowPlayingItem }
        }
        commands.pauseCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.onPause() }
            return .success
        }
        // Headphone clicks and the Control Centre's single button.
        commands.togglePlayPauseCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return .commandFailed }
                let playing =
                    (MPNowPlayingInfoCenter.default().nowPlayingInfo?[
                        MPNowPlayingInfoPropertyPlaybackRate] as? Double ?? 0) > 0
                if playing {
                    self.onPause()
                    return .success
                }
                return self.onPlay() ? .success : .noActionableNowPlayingItem
            }
        }
        // A loop has nowhere to skip or seek to.
        for command in [
            commands.nextTrackCommand, commands.previousTrackCommand,
            commands.skipForwardCommand, commands.skipBackwardCommand,
            commands.changePlaybackPositionCommand, commands.stopCommand,
        ] {
            command.isEnabled = false
        }
    }

    /// The library's forest, which is the picture the app is.
    private static let artwork: MPMediaItemArtwork = {
        let image = UIImage(resource: .libraryBackdrop)
        return MPMediaItemArtwork(boundsSize: image.size) { _ in image }
    }()
}
