// What is behind the sign-in screen: a still, and a film that fades in over
// it once `AVFoundation` has a frame to show.
//
// The still is not a nicety. Opening a 4 MB file and getting the first frame
// onto a layer takes long enough to see, and a black screen for a third of a
// second is the first thing the app would ever show anybody. So the plate is
// drawn immediately, the film arrives on top of it, and on a phone that
// cannot play the file at all the plate is simply what the screen is.

import AVFoundation
import SwiftUI
import UIKit

struct LoginBackdrop: View {
    /// Paused whenever the app is not in front: a loop nobody can see is a
    /// tax on the battery and nothing else.
    var isPlaying: Bool

    @State private var filmIsUp = false

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black

                Image(.loginStill)
                    .resizable()
                    .aspectRatio(contentMode: .fill)

                LoopingFilm(isPlaying: isPlaying, onFirstFrame: { filmIsUp = true })
                    .opacity(filmIsUp ? 1 : 0)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .scaleEffect(LoginAtmosphere.backdropZoom)
            .clipped()
            .animation(.easeIn(duration: LoginAtmosphere.filmFadeIn), value: filmIsUp)
        }
        .accessibilityHidden(true)
    }
}

// ------------------------------------------------------------------ film --

/// The loop itself: an `AVPlayerLayer` under a queue player, which is the
/// one arrangement that loops without a visible seam. `AVPlayerLooper` keeps
/// the next copy of the item queued ahead of the one playing, so the wrap is
/// not a seek.
private struct LoopingFilm: UIViewRepresentable {
    let isPlaying: Bool
    let onFirstFrame: () -> Void

    func makeUIView(context: Context) -> FilmView {
        let view = FilmView()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        context.coordinator.attach(to: view, onFirstFrame: onFirstFrame)
        return view
    }

    func updateUIView(_ view: FilmView, context: Context) {
        context.coordinator.setPlaying(isPlaying)
    }

    static func dismantleUIView(_ view: FilmView, coordinator: Projectionist) {
        coordinator.tearDown()
    }

    func makeCoordinator() -> Projectionist { Projectionist() }

    /// A view whose backing layer *is* the player layer, so there is no
    /// second layer to keep the size of.
    final class FilmView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }

    final class Projectionist {
        private var player: AVQueuePlayer?
        private var looper: AVPlayerLooper?
        private var readiness: NSKeyValueObservation?

        func attach(to view: FilmView, onFirstFrame: @escaping () -> Void) {
            guard
                let url = Bundle.main.url(
                    forResource: LoginAtmosphere.film.name,
                    withExtension: LoginAtmosphere.film.ext)
            else { return }

            let player = AVQueuePlayer()
            // The film's own sound never plays. What this screen sounds
            // like is `LoginAmbience`, and only that.
            player.isMuted = true
            player.volume = 0
            // Scenery has no business holding the display awake.
            player.preventsDisplaySleepDuringVideoPlayback = false

            looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: url))
            view.playerLayer.player = player
            view.playerLayer.videoGravity = .resizeAspectFill

            // The crossfade waits on this rather than on the item's status:
            // `readyToPlay` means the decoder is willing, not that anything
            // has been drawn, and fading in on it shows a black frame.
            readiness = view.playerLayer.observe(
                \.isReadyForDisplay, options: [.initial, .new]
            ) { layer, _ in
                guard layer.isReadyForDisplay else { return }
                DispatchQueue.main.async(execute: onFirstFrame)
            }

            self.player = player
        }

        func setPlaying(_ playing: Bool) {
            guard let player else { return }
            if playing {
                player.play()
            } else {
                player.pause()
            }
        }

        func tearDown() {
            readiness?.invalidate()
            readiness = nil
            player?.pause()
            looper?.disableLooping()
            looper = nil
            player = nil
        }
    }
}

#Preview {
    LoginBackdrop(isPlaying: true)
        .ignoresSafeArea()
}
