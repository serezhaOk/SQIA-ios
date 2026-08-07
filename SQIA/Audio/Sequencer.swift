// What drives the pattern forward.
//
// A timer wakes every 25 ms, asks the clock which steps fall inside the next
// 120 ms, and hands each one to whoever is listening — which turns it into
// notes and schedules them at their exact frame. The timer's own accuracy
// does not matter: the times were decided from the audio clock, so a late
// wake-up simply schedules the same moments from further away.

import Foundation
import SQIACore

final class Sequencer {
    /// Called on the transport queue for each step that comes due.
    /// `lead` is how long until it sounds, which the UI uses to bloom a dot
    /// at the moment the note lands rather than when it was scheduled.
    typealias StepHandler = (_ step: Int, _ frame: Int64, _ lead: Double) -> Void

    var onStep: StepHandler?

    private let engine: AudioEngine
    private let queue = DispatchQueue(
        label: "com.serezhaok.sqia.transport", qos: .userInteractive)
    private var timer: DispatchSourceTimer?

    /// Only touched on `queue`.
    private var clock = StepClock()
    /// Which renderer the clock's times refer to. The engine builds a new
    /// one after a route change, and its frame counter starts from zero, so
    /// the clock has to be told.
    private var boundMixer: ObjectIdentifier?

    private let stateLock = NSLock()
    private var storedBPM: Double = 120
    private var storedPlaying = false

    init(engine: AudioEngine) {
        self.engine = engine
    }

    // -------------------------------------------------------------- control --

    var isPlaying: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return storedPlaying
    }

    var bpm: Double {
        get {
            stateLock.lock()
            defer { stateLock.unlock() }
            return storedBPM
        }
        set {
            let clamped = Tempo.clamp(newValue)
            stateLock.lock()
            storedBPM = clamped
            stateLock.unlock()
            queue.async { [weak self] in self?.clock.bpm = clamped }
        }
    }

    func start() {
        stateLock.lock()
        let alreadyPlaying = storedPlaying
        storedPlaying = true
        stateLock.unlock()
        guard !alreadyPlaying else { return }

        queue.async { [weak self] in
            guard let self else { return }
            let mixer = engine.mixer
            boundMixer = ObjectIdentifier(mixer)
            clock.stop()
            clock.start(now: now(on: mixer))
        }

        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(
            deadline: .now(),
            repeating: StepClock.tickInterval,
            leeway: .milliseconds(2)
        )
        timer.setEventHandler { [weak self] in self?.pump() }
        self.timer = timer
        timer.resume()
    }

    func stop() {
        stateLock.lock()
        storedPlaying = false
        stateLock.unlock()

        timer?.cancel()
        timer = nil
        queue.async { [weak self] in self?.clock.stop() }
        engine.silence()
    }

    // ----------------------------------------------------------------- pump --

    private func now(on mixer: AudioMixer) -> Double {
        Double(mixer.currentFrame) / engine.sampleRate
    }

    private func pump() {
        let mixer = engine.mixer
        let sampleRate = engine.sampleRate
        let now = now(on: mixer)

        // The engine rebuilt itself: new renderer, clock back at zero.
        if boundMixer != ObjectIdentifier(mixer) {
            boundMixer = ObjectIdentifier(mixer)
            clock.resync(now: now)
        }

        // Coming back from a suspension, the next step is minutes in the
        // past. Nobody wants to hear that backlog played out.
        if clock.hasFallenBehind(now: now) {
            clock.resync(now: now)
            mixer.panic()
        }

        for tick in clock.pump(now: now) {
            let frame = Int64((tick.time * sampleRate).rounded())
            onStep?(tick.step, frame, tick.time - now)
        }
    }
}
