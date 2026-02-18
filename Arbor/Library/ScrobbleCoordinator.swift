import Foundation
import ScrobbleKit

actor ScrobbleCoordinator {
    private let scrobbleQueue = ScrobbleQueue()
    private var scrobbleState: ScrobbleState?
    private var seed: ScrobbleSeed?
    private var lastDuration: Double = 0
    private var lastPlaybackTime: Double = 0
    private var didReturnToStart = false

    func startTrack(seed: ScrobbleSeed, duration: Double) {
        self.seed = seed
        lastDuration = duration
        lastPlaybackTime = 0
        didReturnToStart = false
        scrobbleState = ScrobbleState(seed: seed)
        scrobbleState?.updateDuration(duration)
    }

    func updateDuration(_ duration: Double) {
        lastDuration = duration
        scrobbleState?.updateDuration(duration)
    }

    func updateSeed(_ seed: ScrobbleSeed) {
        self.seed = seed
        if let scrobbleState {
            if !scrobbleState.updateMetadata(seed) {
                self.scrobbleState = nil
            }
        } else {
            scrobbleState = ScrobbleState(seed: seed)
            scrobbleState?.updateDuration(lastDuration)
        }
    }

    func handleProgress(
        currentTime: Double,
        isPlaying: Bool,
        isAuthenticated: Bool,
        isScrobblingEnabled: Bool,
        isTrackScrobblingEnabled: Bool,
        manager: SBKManager?
    ) async {
        handleScrobbleResetIfNeeded(currentTime: currentTime, isPlaying: isPlaying)

        // Do not advance scrobble progress for tracks explicitly opted out.
        guard isTrackScrobblingEnabled else { return }

        guard let scrobbleState,
              scrobbleState.shouldScrobble(currentTime: currentTime, isPlaying: isPlaying) else {
            return
        }

        guard isAuthenticated, isScrobblingEnabled else { return }

        scrobbleState.markScrobbled()
        let scrobble = scrobbleState.toCachedScrobble()

        await scrobbleQueue.enqueue(scrobble)
        await scrobbleQueue.flushIfNeeded(manager: manager)
    }

    func flushIfNeeded(manager: SBKManager?) async {
        await scrobbleQueue.flushIfNeeded(manager: manager)
    }

    private func handleScrobbleResetIfNeeded(currentTime: Double, isPlaying: Bool) {
        if currentTime <= 0.05, lastPlaybackTime > 5.0 {
            didReturnToStart = true
        }

        if isPlaying, didReturnToStart, let seed {
            didReturnToStart = false
            scrobbleState = ScrobbleState(seed: seed)
            scrobbleState?.updateDuration(lastDuration)
        }

        lastPlaybackTime = currentTime
    }
}
