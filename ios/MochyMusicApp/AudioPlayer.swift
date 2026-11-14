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
    @Published private(set) var resolvingTrackID: String?

    private var resolutionTask: Task<Void, Never>?
    @Published private(set) var isBuffering = false

    private var player: AVPlayer?
    private var wantsPlayback = false
    private var itemStatusObserver: NSKeyValueObservation?
    private var playbackStatusObserver: NSKeyValueObservation?
    private var playbackNotifications: [NSObjectProtocol] = []
    private var startupTimeoutTask: Task<Void, Never>?
    private var timeObserver: Any?

    init() {
        configureRemoteCommands()
    }

    func play(_ song: CatalogSong) {
        resolutionTask?.cancel()
        resolvingTrackID = song.id
        errorMessage = nil
        resolutionTask = Task { [weak self] in
            guard let self else { return }
            do {
                let streamURL = try await YouTubeStreamResolver.shared.resolve(videoID: song.id)
                guard !Task.isCancelled else { return }
                resolvingTrackID = nil
                startPlayback(Track(title: song.title, artist: song.artist, streamURL: streamURL, artworkURL: song.thumbnailURL))
            } catch {
                guard !Task.isCancelled else { return }
                resolvingTrackID = nil
                errorMessage = error.localizedDescription
            }
        }
    }

    func play(_ track: Track) {
        resolutionTask?.cancel()
        resolvingTrackID = nil
        startPlayback(track)
    }

    private func startPlayback(_ track: Track) {
        guard track.streamURL.scheme?.lowercased() == "https" else {
            errorMessage = "Enter a valid HTTPS audio URL."
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
        itemStatusObserver = nil
        playbackStatusObserver = nil
        playbackNotifications.forEach { NotificationCenter.default.removeObserver($0) }
        playbackNotifications = []
        startupTimeoutTask?.cancel()
        player?.pause()
        currentTrack = track
        elapsedTime = 0
        duration = 0
        errorMessage = nil

        let item = AVPlayerItem(url: track.streamURL)
        let nextPlayer = AVPlayer(playerItem: item)
        player = nextPlayer
        wantsPlayback = true
        isPlaying = false
        isBuffering = true
        observePlayback(nextPlayer, item: item)
        observeTime(for: nextPlayer)
        nextPlayer.play()
        updateNowPlayingInfo()
    }

    func togglePlayback() {
        wantsPlayback ? pause() : resume()
    }

    func pause() {
        wantsPlayback = false
        isBuffering = false
        startupTimeoutTask?.cancel()
        player?.pause()
        isPlaying = false
        updateNowPlayingInfo()
    }

    func resume() {
        guard let player, player.currentItem?.status != .failed else { return }
        wantsPlayback = true
        player.play()
        updateNowPlayingInfo()
    }

    func seek(to value: Double) {
        guard value.isFinite else { return }
        let seconds = min(max(value, 0), duration)
        player?.seek(to: CMTime(seconds: seconds, preferredTimescale: 600))
        elapsedTime = seconds
        updateNowPlayingInfo()
    }

    private func observePlayback(_ observedPlayer: AVPlayer, item: AVPlayerItem) {
        itemStatusObserver = item.observe(\.status, options: [.initial, .new]) { [weak self, weak observedPlayer] item, _ in
            Task { @MainActor [weak self, weak observedPlayer] in
                guard let self, let observedPlayer, self.player === observedPlayer else { return }
                if item.status == .failed {
                    self.reportPlaybackFailure(item.error)
                }
            }
        }
        playbackStatusObserver = observedPlayer.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self] observedPlayer, _ in
            Task { @MainActor [weak self, weak observedPlayer] in
                guard let self, let observedPlayer, self.player === observedPlayer else { return }
                self.isPlaying = observedPlayer.timeControlStatus == .playing
                self.isBuffering = self.wantsPlayback && observedPlayer.timeControlStatus == .waitingToPlayAtSpecifiedRate
                if self.isPlaying { self.startupTimeoutTask?.cancel() }
                self.updateNowPlayingInfo()
            }
        }
        let center = NotificationCenter.default
        playbackNotifications.append(center.addObserver(forName: .AVPlayerItemFailedToPlayToEndTime, object: item, queue: .main) { [weak self, weak observedPlayer] note in
            let error = note.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error
            Task { @MainActor [weak self, weak observedPlayer] in
                guard let self, let observedPlayer, self.player === observedPlayer else { return }
                self.reportPlaybackFailure(error)
            }
        })
        playbackNotifications.append(center.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self, weak observedPlayer] _ in
            Task { @MainActor [weak self, weak observedPlayer] in
                guard let self, let observedPlayer, self.player === observedPlayer else { return }
                self.wantsPlayback = false
                self.isPlaying = false
                self.isBuffering = false
                self.startupTimeoutTask?.cancel()
                self.updateNowPlayingInfo()
            }
        })
        startupTimeoutTask = Task { [weak self, weak observedPlayer] in
            do { try await Task.sleep(for: .seconds(30)) } catch { return }
            guard let self, let observedPlayer, self.player === observedPlayer,
                  self.wantsPlayback, !self.isPlaying, self.elapsedTime == 0 else { return }
            self.reportPlaybackFailure(NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut))
        }
    }

    private func reportPlaybackFailure(_ error: Error?) {
        wantsPlayback = false
        isPlaying = false
        isBuffering = false
        startupTimeoutTask?.cancel()
        player?.pause()
        if let error = error as NSError? {
            errorMessage = "Playback failed: \(error.localizedDescription) (\(error.domain) \(error.code))"
        } else {
            errorMessage = "Playback failed. The audio stream could not be loaded."
        }
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
