// The one place AVFoundation meets the renderer.
//
// The whole graph is a single source node feeding the output. Everything
// that shapes the sound — voices, the slap delay, the limiter — lives inside
// `AudioMixer`, in SQIACore, where it is ordinary code with tests. This file
// exists to hand that renderer a buffer to fill and to keep it running
// through everything a phone does to an audio session.

import AVFoundation
import SQIACore

final class AudioEngine {
    private(set) var mixer: AudioMixer
    private(set) var sampleRate: Double
    private(set) var isRunning = false

    private let engine = AVAudioEngine()
    private let session = AudioSessionController()
    private var source: AVAudioSourceNode?

    /// Raised when the engine had to stop for a reason of its own — an
    /// interruption, a route change — so the transport can follow.
    var onStopped: (() -> Void)?
    /// Raised after the engine rebuilt itself and is playing again.
    var onRestarted: (() -> Void)?

    init() {
        // A provisional rate; `start()` replaces the mixer once the session
        // says what the hardware is really running at.
        sampleRate = AVAudioSession.sharedInstance().sampleRate
        mixer = AudioMixer(sampleRate: sampleRate)
        session.onEvent = { [weak self] event in self?.handle(event) }
    }

    // ------------------------------------------------------------- running --

    func start() throws {
        guard !isRunning else { return }
        try session.activate()

        // Building the mixer for the wrong rate would detune everything and
        // mistune every filter, so it is built after the session is live.
        if abs(session.sampleRate - sampleRate) > 0.5 || source == nil {
            sampleRate = session.sampleRate
            rebuildGraph()
        }

        engine.prepare()
        try engine.start()
        isRunning = true
    }

    func stop() {
        guard isRunning else { return }
        mixer.panic()
        engine.stop()
        isRunning = false
    }

    /// Everything goes quiet at once, without tearing the graph down.
    func silence() {
        mixer.panic()
    }

    private func rebuildGraph() {
        if let existing = source {
            engine.detach(existing)
            source = nil
        }

        let mixer = AudioMixer(sampleRate: sampleRate)
        self.mixer = mixer

        guard
            let format = AVAudioFormat(
                standardFormatWithSampleRate: sampleRate, channels: 2)
        else {
            assertionFailure("could not describe a stereo format at \(sampleRate) Hz")
            return
        }

        // The closure holds the renderer strongly, which costs one retain at
        // setup and none per block — calling through a captured `let` of
        // class type does not touch the reference count.
        let node = AVAudioSourceNode(format: format) { _, _, frameCount, audioBufferList in
            let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
            guard
                buffers.count >= 2,
                let left = buffers[0].mData?.assumingMemoryBound(to: Float.self),
                let right = buffers[1].mData?.assumingMemoryBound(to: Float.self)
            else {
                // A buffer we cannot fill is not a buffer to leave alone:
                // whatever it held before is noise at full volume.
                for buffer in buffers {
                    guard let data = buffer.mData else { continue }
                    UnsafeMutableRawBufferPointer(
                        start: data, count: Int(buffer.mDataByteSize)
                    ).initializeMemory(as: UInt8.self, repeating: 0)
                }
                return noErr
            }

            mixer.render(frameCount: Int(frameCount), left: left, right: right)
            return noErr
        }

        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        source = node
    }

    // -------------------------------------------------------- interruptions --

    private func handle(_ event: AudioSessionController.Event) {
        switch event {
        case .interrupted, .outputDisconnected:
            // A call arrived or the headphones came out. Stop cleanly; the
            // user decides when to start again.
            stop()
            onStopped?()

        case .resumable:
            restart()

        case .routeChangedIncompatibly, .mediaServicesReset:
            // The graph was built for hardware that is no longer there.
            let wasRunning = isRunning
            engine.stop()
            isRunning = false
            source = nil
            sampleRate = session.sampleRate
            if wasRunning {
                restart()
            } else {
                onStopped?()
            }
        }
    }

    private func restart() {
        do {
            try start()
            onRestarted?()
        } catch {
            isRunning = false
            onStopped?()
        }
    }
}
