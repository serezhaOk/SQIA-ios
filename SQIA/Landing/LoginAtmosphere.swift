// The sign-in screen's picture and its sound, and the knobs for both.
//
// The film is scenery: it loops, it is muted, and it never keeps the screen
// awake. The sound is a separate file on purpose — swapping the track means
// dropping a new `login-audio.wav` into `Resources/Login`, with no re-encode
// and nothing to touch in the picture. Everything worth turning is a
// constant here rather than a number buried in a view.

import AVFoundation
import SwiftUI

enum LoginAtmosphere {
    /// The loop behind the wordmark. Muted, always: its own track is not
    /// what this screen sounds like.
    static let film = (name: "loop-bg-login", ext: "mp4")

    /// The bed under it. This is the one to replace.
    static let ambience = (name: "login-audio", ext: "wav")

    /// Quiet on purpose — this plays under the first screen of the app,
    /// often in a room where nobody asked for it. Raise it here.
    static let ambienceVolume: Float = 0.15

    /// It comes up rather than starting at level, which at this volume is
    /// the difference between an atmosphere and a noise.
    static let ambienceFadeIn: TimeInterval = 1.6
    static let ambienceFadeOut: TimeInterval = 0.35

    /// How long the still holds before the film crosses over it.
    static let filmFadeIn: TimeInterval = 0.45

    /// The mock hangs a 917-tall plate behind an 852-tall screen, so the
    /// picture is a touch wider than a plain fill would make it. Matching
    /// that keeps the shaft of light where the design put it.
    static let backdropZoom: CGFloat = 917.0 / 852.0
}

/// The looping bed under the sign-in screen.
///
/// `.ambient` rather than `.playback`: this is scenery, so it goes quiet
/// with the ring switch and never interrupts whatever the phone was already
/// playing. The sequencer's session is `.playback` and is set when a project
/// opens, which is after this has stopped.
@MainActor
final class LoginAmbience {
    private var player: AVAudioPlayer?
    private var fadeOut: DispatchWorkItem?

    func start() {
        // A start during a fade-out rescues the player mid-ramp rather than
        // restarting it, so going away and coming straight back is not a
        // dip to silence and a fresh 1.6 seconds.
        fadeOut?.cancel()
        fadeOut = nil

        if player == nil { player = load() }
        guard let player else { return }

        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.ambient)
        try? session.setActive(true)

        if !player.isPlaying {
            player.volume = 0
            player.play()
        }
        player.setVolume(LoginAtmosphere.ambienceVolume, fadeDuration: LoginAtmosphere.ambienceFadeIn)
    }

    func stop() {
        guard let player, player.isPlaying else { return }
        player.setVolume(0, fadeDuration: LoginAtmosphere.ambienceFadeOut)

        // Stopped only once it is inaudible; cutting the player at full
        // volume is a click.
        let cut = DispatchWorkItem { [weak player] in
            player?.stop()
            player?.currentTime = 0
        }
        fadeOut = cut
        DispatchQueue.main.asyncAfter(
            deadline: .now() + LoginAtmosphere.ambienceFadeOut, execute: cut)
    }

    private func load() -> AVAudioPlayer? {
        guard
            let url = Bundle.main.url(
                forResource: LoginAtmosphere.ambience.name,
                withExtension: LoginAtmosphere.ambience.ext)
        else { return nil }
        let player = try? AVAudioPlayer(contentsOf: url)
        player?.numberOfLoops = -1
        player?.prepareToPlay()
        return player
    }
}
