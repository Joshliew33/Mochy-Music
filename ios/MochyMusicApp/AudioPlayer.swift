import AVFoundation
import Combine
import MediaPlayer
import Network
import UIKit

@MainActor
final class AudioPlayer: ObservableObject {
    @Published private(set) var currentTrack: Track?
    @Published private(set) var currentSong: CatalogSong?
    @Published private(set) var queue: PlaybackQueue
    @Published private(set) var isPlaying = false
    @Published private(set) var isBuffering = false
    @Published private(set) var elapsedTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var resolvingTrackID: String?
    @Published var errorMessage: String?

    private let library: LibraryStore
    private var player: AVPlayer?
    private var wantsPlayback = false
    private var resumeAfterInterruption = false
    private var resolutionTask: Task<Void, Never>?
    private var startupTimeoutTask: Task<Void, Never>?
    private var artworkTask: Task<Void, Never>?
    private var loadID = UUID()
    private var retries = 0
    private var recoveryScheduled = false
    private var recordedHistory = false
    private var pendingRecovery: Double?
    private var seekAfterLoad: Double = 0
    private var artwork: MPMediaItemArtwork?
    private var imageCache: [URL: UIImage] = [:]
    private var itemStatusObserver: NSKeyValueObservation?
    private var playbackStatusObserver: NSKeyValueObservation?
    private var playbackNotifications: [NSObjectProtocol] = []
    private var sessionNotifications: [NSObjectProtocol] = []
    private var timeObserver: Any?
    private let networkMonitor = NWPathMonitor()
    private var isConnected = true

    init(library: LibraryStore) {
        self.library = library
        self.queue = library.data.queue
        self.currentSong = queue.currentSong
        configureRemoteCommands()
        observeSession()
        networkMonitor.pathUpdateHandler = { [weak self] path in
            let connected = path.status == .satisfied
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isConnected = connected
                if connected, let position = self.pendingRecovery, let song = self.currentSong, self.wantsPlayback {
                    self.pendingRecovery = nil
                    self.resolve(song, position: position, resetRetries: true)
                }
            }
        }
        networkMonitor.start(queue: DispatchQueue(label: "app.mochy.network"))
    }

    func play(_ song: CatalogSong) { play([song], startAt: 0) }
    func play(_ songs: [CatalogSong], startAt index: Int = 0) {
        guard !songs.isEmpty else { return }
        queue.replace(with: songs, startAt: index); persistQueue()
        if let song = queue.currentSong { resolve(song, resetRetries: true) }
    }
    func enqueue(_ song: CatalogSong, playNext: Bool = false) {
        queue.enqueue(song, playNext: playNext)
        if currentSong == nil && currentTrack == nil { currentSong = queue.currentSong }
        persistQueue()
    }
    func selectQueueEntry(_ id: UUID) {
        if let song = queue.select(id) { persistQueue(); resolve(song, resetRetries: true) }
    }
    func moveQueue(from offsets: IndexSet, to destination: Int) {
        queue.move(from: offsets, to: destination); persistQueue()
    }
    func removeQueueEntry(_ id: UUID) {
        let removedCurrent = queue.currentID == id
        let shouldPlay = wantsPlayback
        queue.remove(id); persistQueue()
        if removedCurrent {
            stopPlayer()
            currentSong = queue.currentSong
            if shouldPlay, let song = currentSong { resolve(song, resetRetries: true) }
        }
    }
    func clearQueue() {
        stopPlayer(); queue.replace(with: []); currentSong = nil; persistQueue(); updateNowPlayingInfo()
    }
    func restoreSavedQueue() {
        stopPlayer(); queue = library.data.queue; currentSong = queue.currentSong; updateNowPlayingInfo()
    }
    func toggleShuffle() { queue.setShuffle(!queue.isShuffled); persistQueue() }
    func cycleRepeat() {
        let modes = RepeatMode.allCases
        queue.repeatMode = modes[(modes.firstIndex(of: queue.repeatMode)! + 1) % modes.count]
        persistQueue()
    }
    func next() {
        if let song = queue.advance(automatically: false) { persistQueue(); resolve(song, resetRetries: true) }
    }
    func previous() {
        if elapsedTime > 3 { seek(to: 0); return }
        if let song = queue.previous() { persistQueue(); resolve(song, resetRetries: true) }
    }
    private func persistQueue() {
        library.saveQueue(queue)
        MPRemoteCommandCenter.shared().nextTrackCommand.isEnabled = queue.canNext
        MPRemoteCommandCenter.shared().previousTrackCommand.isEnabled = queue.canPrevious || currentSong != nil
    }

    private func resolve(_ song: CatalogSong, position: Double = 0, resetRetries: Bool) {
        resolutionTask?.cancel(); tearDownPlayer()
        loadID = UUID(); let requestID = loadID
        recoveryScheduled = false
        if resetRetries { retries = 0; recordedHistory = false }
        currentSong = song; currentTrack = nil; artwork = nil
        resolvingTrackID = song.id; errorMessage = nil; wantsPlayback = true
        isBuffering = true; isPlaying = false; elapsedTime = position; duration = song.durationSeconds ?? 0
        seekAfterLoad = position; pendingRecovery = nil
        updateNowPlayingInfo()
        resolutionTask = Task { [weak self] in
            guard let self else { return }
            do {
                let url = try await YouTubeStreamResolver.shared.resolve(videoID: song.id)
                try Task.checkCancellation()
                guard self.loadID == requestID else { return }
                self.resolvingTrackID = nil
                self.startPlayback(Track(title: song.title, artist: song.artist, streamURL: url, artworkURL: song.thumbnailURL, httpUserAgent: YouTubeStreamResolver.userAgent))
            } catch {
                guard !Task.isCancelled, self.loadID == requestID else { return }
                self.resolvingTrackID = nil; self.reportPlaybackFailure(error)
            }
        }
    }

    func play(_ track: Track) {
        resolutionTask?.cancel(); tearDownPlayer(); loadID = UUID()
        currentSong = nil; retries = 0; elapsedTime = 0; duration = 0; seekAfterLoad = 0
        startPlayback(track)
    }
    private func startPlayback(_ track: Track) {
        guard track.streamURL.scheme?.lowercased() == "https" else { reportPlaybackFailure(URLError(.unsupportedURL)); return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
        } catch { reportPlaybackFailure(error); return }
        currentTrack = track; errorMessage = nil
        var options: [String: Any] = [:]
        if let userAgent = track.httpUserAgent { options[AVURLAssetHTTPUserAgentKey] = userAgent }
        let item = AVPlayerItem(asset: AVURLAsset(url: track.streamURL, options: options))
        let next = AVPlayer(playerItem: item)
        player = next; wantsPlayback = true; isBuffering = true; isPlaying = false
        observePlayback(next, item: item); observeTime(for: next); loadArtwork(track.artworkURL)
        if seekAfterLoad == 0 { next.play() }
        armTimeout(next); updateNowPlayingInfo()
    }

    func togglePlayback() { wantsPlayback ? pause() : resume() }
    func pause() {
        recoveryScheduled = false
        wantsPlayback = false; pendingRecovery = nil; resumeAfterInterruption = false
        resolutionTask?.cancel(); startupTimeoutTask?.cancel(); resolvingTrackID = nil
        isBuffering = false; isPlaying = false; player?.pause(); updateNowPlayingInfo()
    }
    func resume() {
        if let player, player.currentItem?.status != .failed {
            do { try AVAudioSession.sharedInstance().setActive(true) } catch { reportPlaybackFailure(error); return }
            wantsPlayback = true; errorMessage = nil; player.play(); armTimeout(player)
        } else if let song = currentSong { resolve(song, position: elapsedTime, resetRetries: true) }
        updateNowPlayingInfo()
    }
    func seek(to value: Double) {
        guard value.isFinite, duration > 0 else { return }
        let position = min(max(value, 0), duration)
        player?.seek(to: CMTime(seconds: position, preferredTimescale: 600))
        elapsedTime = position; updateNowPlayingInfo()
    }
    private func stopPlayer() {
        resolutionTask?.cancel(); loadID = UUID(); tearDownPlayer()
        currentTrack = nil; wantsPlayback = false; isPlaying = false; isBuffering = false
        elapsedTime = 0; duration = 0; resolvingTrackID = nil; pendingRecovery = nil; artwork = nil
    }
    private func tearDownPlayer() {
        startupTimeoutTask?.cancel(); artworkTask?.cancel()
        itemStatusObserver = nil; playbackStatusObserver = nil
        playbackNotifications.forEach { NotificationCenter.default.removeObserver($0) }; playbackNotifications = []
        if let timeObserver, let player { player.removeTimeObserver(timeObserver) }
        timeObserver = nil; player?.pause(); player = nil
    }
    private func armTimeout(_ observed: AVPlayer) {
        startupTimeoutTask?.cancel()
        let startingPosition = elapsedTime
        startupTimeoutTask = Task { [weak self, weak observed] in
            do { try await Task.sleep(for: .seconds(30)) } catch { return }
            guard let self, let observed, self.player === observed, self.wantsPlayback,
                  !self.isPlaying, self.elapsedTime <= startingPosition + 0.1 else { return }
            self.reportPlaybackFailure(URLError(.timedOut))
        }
    }
    private func observePlayback(_ observed: AVPlayer, item: AVPlayerItem) {
        itemStatusObserver = item.observe(\.status, options: [.initial, .new]) { [weak self, weak observed] item, _ in
            Task { @MainActor [weak self, weak observed] in
                guard let self, let observed, self.player === observed else { return }
                if item.status == .failed { self.reportPlaybackFailure(item.error) }
                else if item.status == .readyToPlay && self.seekAfterLoad > 0 {
                    let position = self.seekAfterLoad; self.seekAfterLoad = 0
                    await observed.seek(to: CMTime(seconds: position, preferredTimescale: 600))
                    guard self.player === observed else { return }
                    if self.wantsPlayback { observed.play() }
                }
            }
        }
        playbackStatusObserver = observed.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self] observed, _ in
            Task { @MainActor [weak self, weak observed] in
                guard let self, let observed, self.player === observed else { return }
                self.isPlaying = observed.timeControlStatus == .playing
                self.isBuffering = self.wantsPlayback && observed.timeControlStatus == .waitingToPlayAtSpecifiedRate
                if self.isPlaying {
                    self.startupTimeoutTask?.cancel(); self.errorMessage = nil
                    if !self.recordedHistory, let song = self.currentSong { self.library.recordPlay(song); self.recordedHistory = true }
                }
                self.updateNowPlayingInfo()
            }
        }
        let center = NotificationCenter.default
        playbackNotifications.append(center.addObserver(forName: .AVPlayerItemFailedToPlayToEndTime, object: item, queue: .main) { [weak self, weak observed] note in
            let error = note.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error
            Task { @MainActor [weak self, weak observed] in
                guard let self, let observed, self.player === observed else { return }; self.reportPlaybackFailure(error)
            }
        })
        playbackNotifications.append(center.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self, weak observed] _ in
            Task { @MainActor [weak self, weak observed] in
                guard let self, let observed, self.player === observed else { return }
                if self.currentSong != nil, let next = self.queue.advance(automatically: true) {
                    self.persistQueue(); self.resolve(next, resetRetries: true)
                } else { self.pause() }
            }
        })
        playbackNotifications.append(center.addObserver(forName: .AVPlayerItemPlaybackStalled, object: item, queue: .main) { [weak self, weak observed] _ in
            Task { @MainActor [weak self, weak observed] in
                guard let self, let observed, self.player === observed, self.wantsPlayback else { return }
                self.isBuffering = true; self.armTimeout(observed)
            }
        })
    }
    private func reportPlaybackFailure(_ error: Error?) {
        guard !recoveryScheduled else { return }
        startupTimeoutTask?.cancel(); player?.pause(); isPlaying = false; isBuffering = false
        let position = elapsedTime
        if currentSong != nil, wantsPlayback, !isConnected {
            recoveryScheduled = true
            pendingRecovery = position; errorMessage = "网络已断开，恢复连接后将重试。"; return
        }
        if let song = currentSong, wantsPlayback, retries < 2 {
            recoveryScheduled = true
            retries += 1; errorMessage = "正在重新获取播放地址（\(retries)/2）…"; isBuffering = true
            let expected = loadID
            resolutionTask = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(2)) } catch { return }
                guard let self, self.loadID == expected, self.wantsPlayback else { return }
                self.resolve(song, position: position, resetRetries: false)
            }
            return
        }
        wantsPlayback = false
        if let error = error as NSError? { errorMessage = "播放失败：\(error.localizedDescription)（\(error.domain) \(error.code)）" }
        else { errorMessage = "音频无法加载，请重试或更换歌曲。" }
        updateNowPlayingInfo()
    }
    private func observeTime(for observed: AVPlayer) {
        timeObserver = observed.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main) { [weak self, weak observed] time in
            Task { @MainActor [weak self, weak observed] in
                guard let self, let observed, self.player === observed else { return }
                if time.seconds.isFinite { self.elapsedTime = time.seconds }
                let seconds = observed.currentItem?.duration.seconds ?? 0
                if seconds.isFinite && seconds > 0 { self.duration = seconds }
                self.updateNowPlayingInfo()
            }
        }
    }
    private func observeSession() {
        let center = NotificationCenter.default
        sessionNotifications.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            let options = note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            Task { @MainActor [weak self] in
                guard let self, let raw, let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
                if type == .began { let wasPlaying = self.wantsPlayback; self.pause(); self.resumeAfterInterruption = wasPlaying }
                else { let resume = self.resumeAfterInterruption; self.resumeAfterInterruption = false; if resume && AVAudioSession.InterruptionOptions(rawValue: options).contains(.shouldResume) { self.resume() } }
            }
        })
        sessionNotifications.append(center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] note in
            let reason = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            Task { @MainActor [weak self] in if reason == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue { self?.pause() } }
        })
        sessionNotifications.append(center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in guard let self, let song = self.currentSong, self.wantsPlayback else { return }; self.resolve(song, position: self.elapsedTime, resetRetries: true) }
        })
    }
    private func configureRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak self] _ in Task { @MainActor in self?.resume() }; return .success }
        center.pauseCommand.addTarget { [weak self] _ in Task { @MainActor in self?.pause() }; return .success }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in Task { @MainActor in self?.togglePlayback() }; return .success }
        center.nextTrackCommand.addTarget { [weak self] _ in Task { @MainActor in self?.next() }; return .success }
        center.previousTrackCommand.addTarget { [weak self] _ in Task { @MainActor in self?.previous() }; return .success }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            Task { @MainActor in self?.seek(to: event.positionTime) }; return .success
        }
        center.nextTrackCommand.isEnabled = queue.canNext
        center.previousTrackCommand.isEnabled = currentSong != nil
    }
    private func loadArtwork(_ url: URL?) {
        artwork = nil
        guard let url else { return }
        if let image = imageCache[url] { artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }; return }
        let expected = currentTrack?.id
        artworkTask = Task { [weak self] in
            do {
                let (bytes, response) = try await URLSession.shared.data(from: url)
                guard !Task.isCancelled, let self, self.currentTrack?.id == expected,
                      (response as? HTTPURLResponse)?.statusCode == 200, let image = UIImage(data: bytes) else { return }
                if self.imageCache.count >= 20 { self.imageCache.removeAll() }
                self.imageCache[url] = image; self.artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }; self.updateNowPlayingInfo()
            } catch {}
        }
    }
    private func updateNowPlayingInfo() {
        guard currentTrack != nil || currentSong != nil else { MPNowPlayingInfoCenter.default().nowPlayingInfo = nil; return }
        var info: [String: Any] = [MPMediaItemPropertyTitle: currentSong?.title ?? currentTrack?.title ?? "", MPMediaItemPropertyArtist: currentSong?.artist ?? currentTrack?.artist ?? "", MPNowPlayingInfoPropertyElapsedPlaybackTime: elapsedTime, MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0]
        if duration.isFinite && duration > 0 { info[MPMediaItemPropertyPlaybackDuration] = duration }
        if let artwork { info[MPMediaItemPropertyArtwork] = artwork }
        if let position = queue.position { info[MPNowPlayingInfoPropertyPlaybackQueueIndex] = position; info[MPNowPlayingInfoPropertyPlaybackQueueCount] = queue.entries.count }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}
