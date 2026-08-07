// The system side of playing audio: what the app is allowed to do with the
// speaker, and everything that can interrupt it.
//
// A phone takes audio away far more often than a browser tab does — a call
// arrives, headphones come out, the app is suspended, the media server dies.
// Each of those is handled here, and each one ends with a decision the
// engine acts on rather than a surprise.

import AVFoundation
import Foundation

final class AudioSessionController {
    enum Event {
        /// Something else took the audio. Stop and wait.
        case interrupted
        /// It gave it back, and asked us to carry on.
        case resumable
        /// The route changed and the engine has to be rebuilt — usually a
        /// different sample rate on a new device.
        case routeChangedIncompatibly
        /// Headphones were unplugged. Every phone stops playing here, and a
        /// music app that does not is a rude one.
        case outputDisconnected
        /// The media server restarted; nothing survives it.
        case mediaServicesReset
    }

    /// Delivered on the main queue.
    var onEvent: ((Event) -> Void)?

    private var observers: [NSObjectProtocol] = []
    private var configuredSampleRate: Double = 0

    /// The rate the hardware is actually running at. The DSP is built for a
    /// specific rate, so this is read once and rebuilt on if it changes.
    var sampleRate: Double {
        AVAudioSession.sharedInstance().sampleRate
    }

    func activate() throws {
        let session = AVAudioSession.sharedInstance()
        // A sequencer is a music app: it plays through the silent switch,
        // and it does not mix with other audio, because it is the audio.
        try session.setCategory(.playback, mode: .default)
        try session.setActive(true)
        configuredSampleRate = session.sampleRate
        observe()
    }

    func deactivate() {
        try? AVAudioSession.sharedInstance().setActive(false)
    }

    private func observe() {
        guard observers.isEmpty else { return }
        let centre = NotificationCenter.default
        let session = AVAudioSession.sharedInstance()

        observers.append(
            centre.addObserver(
                forName: AVAudioSession.interruptionNotification,
                object: session,
                queue: .main
            ) { [weak self] note in
                self?.handleInterruption(note)
            })

        observers.append(
            centre.addObserver(
                forName: AVAudioSession.routeChangeNotification,
                object: session,
                queue: .main
            ) { [weak self] note in
                self?.handleRouteChange(note)
            })

        observers.append(
            centre.addObserver(
                forName: AVAudioSession.mediaServicesWereResetNotification,
                object: session,
                queue: .main
            ) { [weak self] _ in
                self?.onEvent?(.mediaServicesReset)
            })
    }

    private func handleInterruption(_ note: Notification) {
        guard
            let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
            let type = AVAudioSession.InterruptionType(rawValue: raw)
        else { return }

        switch type {
        case .began:
            onEvent?(.interrupted)
        case .ended:
            let options = (note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt)
                .map(AVAudioSession.InterruptionOptions.init(rawValue:)) ?? []
            // Only resume when the system says the interruption is over and
            // we are welcome back; otherwise stay stopped.
            if options.contains(.shouldResume) {
                try? AVAudioSession.sharedInstance().setActive(true)
                onEvent?(.resumable)
            }
        @unknown default:
            onEvent?(.interrupted)
        }
    }

    private func handleRouteChange(_ note: Notification) {
        guard
            let raw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
            let reason = AVAudioSession.RouteChangeReason(rawValue: raw)
        else { return }

        if reason == .oldDeviceUnavailable {
            onEvent?(.outputDisconnected)
            return
        }

        // A new device can run at a different rate, and every filter
        // coefficient in the engine was computed for the old one.
        let current = AVAudioSession.sharedInstance().sampleRate
        if abs(current - configuredSampleRate) > 0.5 {
            configuredSampleRate = current
            onEvent?(.routeChangedIncompatibly)
        }
    }

    deinit {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
    }
}
