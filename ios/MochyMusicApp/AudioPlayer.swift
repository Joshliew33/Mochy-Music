import AVFoundation
import Combine
import MediaPlayer

@MainActor
final class AudioPlayer: ObservableObject {
    @Published private(set) var currentTrack: Track?
    @Published private(set) var isPlaying = false
    @Published private(set) var elapsedTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    @Published var errorMessage: String?

    private var player: AVPlayer?
    private var timeObserver: Any?

    init() {
        configureRemoteCommands()
    }

    func play(_ track: Track) {
        guard ["https", "http"].contains(track.streamURL.scheme?.lowercased() ?? "") else {
            errorMessage = "Enter a valid HTTP or HTTPS audio URL."
            return
        }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
        } catch {
            errorMessage = error.localizedDescription
            return
        }

        removeTimeObserver()
        currentTrack = track
        elapsedTime = 0
        duration = 0
        errorMessage = nil

        let nextPlayer = AVPlayer(url: track.streamURL)
        player = nextPlayer
        observeTime(for: nextPlayer)
        nextPlayer.play()
        isPlaying = true
        updateNowPlayingInfo()
    }

    func togglePlayback() {
        isPlaying ? pause() : resume()
    }

    func pause() {
        player?.pause()
        isPlaying = false
        updateNowPlayingInfo()
    }

    func resume() {
        guard player != nil else { return }
        player?.play()
        isPlaying = true
        updateNowPlayingInfo()
    }

    func seek(to value: Double) {
        guard value.isFinite else { return }
        let seconds = min(max(value, 0), duration)
        player?.seek(to: CMTime(seconds: seconds, preferredTimescale: 600))
        elapsedTime = seconds
        updateNowPlayingInfo()
    }

    private func observeTime(for player: AVPlayer) {
        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self, weak player] time in
            Task { @MainActor [weak self, weak player] in
                guard let self, let player else { return }
                if time.seconds.isFinite {
                    self.elapsedTime = time.seconds
                }
                let itemDuration = player.currentItem?.duration.seconds ?? 0
                if itemDuration.isFinite && itemDuration > 0 {
                    self.duration = itemDuration
                }
                self.updateNowPlayingInfo()
            }
        }
    }

    private func removeTimeObserver() {
        if let timeObserver, let player {
            player.removeTimeObserver(timeObserver)
        }
        timeObserver = nil
    }

    private func configureRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()

        center.playCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in self?.resume() }
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in self?.pause() }
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in self?.togglePlayback() }
            return .success
        }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            Task { @MainActor [weak self] in self?.seek(to: event.positionTime) }
            return .success
        }

        center.nextTrackCommand.isEnabled = false
        center.previousTrackCommand.isEnabled = false
    }

    private func updateNowPlayingInfo() {
        guard let currentTrack else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }

        var info: [String: Any] = [
            MPMediaItemPropertyTitle: currentTrack.title,
            MPMediaItemPropertyArtist: currentTrack.artist,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: elapsedTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0
        ]
        if duration.isFinite && duration > 0 {
            info[MPMediaItemPropertyPlaybackDuration] = duration
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}
