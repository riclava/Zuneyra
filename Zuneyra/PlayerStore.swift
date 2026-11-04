import SwiftUI
import AVFoundation
import MediaPlayer
import Observation

@MainActor @Observable
final class PlayerStore {
    var tracks: [Track] = []
    var current: Track?
    var isPlaying = false
    var position = 0.0
    var isImporting = false
    var importProgress = ""
    var importReport: ImportReport?
    var errorMessage: String?
    var isLoading = true
    private(set) var queue: [Track] = []
    let repository: MusicRepository
    private let preferences: UserDefaults
    private let sharedDocumentsURL: URL?
    private let resources = PlaybackResources()
    private var player: AVPlayer { resources.player }
    private var itemObservation: NSKeyValueObservation?
    private var rateObservation: NSKeyValueObservation?
    private var lastCheckpoint = -1
    private var generation = 0
    private var hasStartedLoading = false
    private var isPreparing = false
    private var isSeeking = false
    private var seekRevision = 0
    private var wantsPlayback = false
    private var importTask: Task<Void, Never>?
    private var resumeAfterInterruption = false

    init(repository: MusicRepository = MusicRepository(), preferences: UserDefaults = .standard, sharedDocumentsURL: URL? = SharedDocumentsLocation.defaultURL) {
        self.preferences = preferences
        self.repository = repository
        self.sharedDocumentsURL = sharedDocumentsURL
        resources.timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, !self.isPreparing, !self.isSeeking else { return }
                // A queued callback can contain a pre-seek time. Read the current
                // clock here so it cannot overwrite the restored/scrubbed position.
                let seconds = self.player.currentTime().seconds
                guard seconds.isFinite else { return }
                self.position = max(0, seconds)
                let checkpoint = Int(self.position) / 5
                if checkpoint != self.lastCheckpoint { self.lastCheckpoint = checkpoint; self.saveSession() }
            }
        }
        rateObservation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            let playing = player.timeControlStatus == .playing
            Task { @MainActor [weak self] in self?.isPlaying = playing; self?.updateNowPlaying() }
        }
        resources.notifications.append(NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: nil, queue: .main) { [weak self] note in
            let finishedItem = note.object as? AVPlayerItem
            Task { @MainActor [weak self] in
                guard let self, let item = finishedItem, item === self.player.currentItem else { return }
                self.next(automatically: true)
            }
        })
        #if os(iOS)
        resources.notifications.append(NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] note in
            let reason = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            if reason == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue { Task { @MainActor [weak self] in self?.pause() } }
        })
        resources.notifications.append(NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            let type = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            let options = note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            Task { @MainActor [weak self] in
                guard let self else { return }
                if type == AVAudioSession.InterruptionType.began.rawValue {
                    self.resumeAfterInterruption = self.isPlaying
                    self.player.pause()
                } else if self.resumeAfterInterruption && AVAudioSession.InterruptionOptions(rawValue: options).contains(.shouldResume) {
                    self.resumeAfterInterruption = false; self.resume()
                }
            }
        })
        #endif
        configureRemoteCommands()
    }


    func load() async {
        guard !hasStartedLoading else { return }
        hasStartedLoading = true
        do {
            tracks = try await repository.load()
            if let data = preferences.data(forKey: "playbackSession"), let saved = try? JSONDecoder().decode(Session.self, from: data) {
                queue = saved.queue.compactMap { id in tracks.first { $0.id == id } }
                if let track = tracks.first(where: { $0.id == saved.current }) {
                    await prepare(track, autoplay: false, offset: saved.position)
                }
            }
        } catch { errorMessage = error.localizedDescription }
        isLoading = false
        scanSharedDocuments()
    }

    func scanSharedDocuments() {
        guard !isLoading, !isImporting, let sharedDocumentsURL else { return }
        isImporting = true
        importProgress = "正在检查电脑传入的音乐…"
        importTask = Task {
            do {
                let report = try await repository.importSharedDocuments(from: sharedDocumentsURL) { [weak self] completed, total in
                    await MainActor.run { [weak self] in self?.importProgress = "正在导入电脑音乐 \(completed) / \(total)" }
                }
                tracks = try await repository.load()
                if report.added > 0 || report.duplicates > 0 || !report.failures.isEmpty { importReport = report }
            } catch is CancellationError { /* The next scan can retry unprocessed files. */ }
            catch { errorMessage = error.localizedDescription }
            isImporting = false
            importTask = nil
        }
    }

    func importFiles(_ urls: [URL]) {
        guard !isImporting else { return }
        isImporting = true; importProgress = "正在准备文件…"
        importTask = Task {
            do {
                let report = try await repository.importFiles(urls) { [weak self] completed, total in
                    await MainActor.run { [weak self] in self?.importProgress = "正在导入 \(completed) / \(total)" }
                }
                tracks = try await repository.load()
                importReport = report
            } catch { errorMessage = error.localizedDescription }
            isImporting = false
            importTask = nil
        }
    }
    func cancelImport() { importTask?.cancel() }

    func play(_ track: Track, context: [Track]) {
        queue = context.isEmpty ? [track] : context
        Task { await prepare(track, autoplay: true) }
    }
    private func prepare(_ track: Track, autoplay: Bool, offset: Double = 0) async {
        generation += 1
        let request = generation
        isPreparing = true
        seekRevision += 1
        isSeeking = false
        wantsPlayback = autoplay
        player.pause()
        player.replaceCurrentItem(with: nil)
        current = track; position = 0
        let url = await repository.mediaURL(for: track)
        guard request == generation else { return }
        guard FileManager.default.fileExists(atPath: url.path) else { isPreparing = false; errorMessage = "找不到「\(track.title)」的本地文件。"; return }
        let item = AVPlayerItem(url: url)
        itemObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            guard item.status == .failed else { return }
            let message = item.error?.localizedDescription ?? "无法播放此音频"
            Task { @MainActor [weak self] in
                guard let self, request == self.generation else { return }
                self.pause(); self.errorMessage = message
            }
        }
        player.replaceCurrentItem(with: item)
        position = min(max(0, offset), track.duration)
        if position > 0 { await player.seek(to: CMTime(seconds: position, preferredTimescale: 600)) }
        guard request == generation else { return }
        isPreparing = false
        if wantsPlayback { resume() }
        saveSession(); updateNowPlaying()
    }
    func toggle() { if isPlaying || player.timeControlStatus == .waitingToPlayAtSpecifiedRate { pause() } else { resume() } }
    func resume() {
        guard current != nil else { return }
        wantsPlayback = true
        guard !isPreparing else { return }
        do {
            #if os(iOS)
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
            #endif
            if position >= (current?.duration ?? 0) { seek(to: 0) }
            player.play()
        } catch { errorMessage = error.localizedDescription }
    }
    func pause() { wantsPlayback = false; resumeAfterInterruption = false; player.pause(); isPlaying = false; saveSession(); updateNowPlaying() }
    func seek(to seconds: Double) {
        guard let current else { return }
        position = min(max(0, seconds), current.duration)
        seekRevision += 1
        let revision = seekRevision
        isSeeking = true
        player.seek(to: CMTime(seconds: position, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.seekRevision == revision else { return }
                self.isSeeking = false
            }
        }
        saveSession(); updateNowPlaying()
    }
    func next(automatically: Bool = false) {
        guard let current, let index = queue.firstIndex(where: { $0.id == current.id }) else { return }
        guard index + 1 < queue.count else { pause(); if automatically { position = current.duration }; return }
        play(queue[index + 1], context: queue)
    }
    func previous() {
        if position > 3 { seek(to: 0); return }
        guard let current, let index = queue.firstIndex(where: { $0.id == current.id }), index > 0 else { seek(to: 0); return }
        play(queue[index - 1], context: queue)
    }
    func toggleFavorite(_ track: Track) {
        Task {
            var updated = track; updated.favorite.toggle()
            do {
                try await repository.save(updated)
                if let index = tracks.firstIndex(where: { $0.id == track.id }) { tracks[index] = updated }
                if current?.id == track.id { current = updated }
            } catch { errorMessage = error.localizedDescription }
        }
    }
    private struct Session: Codable { let current: UUID; let queue: [UUID]; let position: Double }
    func saveSession() {
        guard let current else { return }
        if let data = try? JSONEncoder().encode(Session(current: current.id, queue: queue.map(\.id), position: position)) { preferences.set(data, forKey: "playbackSession") }
    }
    private func updateNowPlaying() {
        guard let current else { return }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [MPMediaItemPropertyTitle: current.title, MPMediaItemPropertyArtist: current.artist, MPMediaItemPropertyAlbumTitle: current.album, MPMediaItemPropertyPlaybackDuration: current.duration, MPNowPlayingInfoPropertyElapsedPlaybackTime: position, MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0]
        #if os(macOS)
        MPNowPlayingInfoCenter.default().playbackState = isPlaying ? .playing : .paused
        #endif
    }
    private func configureRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        func bind(_ command: MPRemoteCommand, action: @escaping @MainActor () -> Void) {
            let token = command.addTarget { _ in Task { @MainActor in action() }; return .success }
            resources.remoteTargets.append((command, token))
        }
        bind(center.playCommand) { [weak self] in self?.resume() }
        bind(center.pauseCommand) { [weak self] in self?.pause() }
        bind(center.togglePlayPauseCommand) { [weak self] in self?.toggle() }
        bind(center.nextTrackCommand) { [weak self] in self?.next() }
        bind(center.previousTrackCommand) { [weak self] in self?.previous() }
        let token = center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            let value = event.positionTime
            Task { @MainActor [weak self] in self?.seek(to: value) }; return .success
        }
        resources.remoteTargets.append((center.changePlaybackPositionCommand, token))
    }
}

enum SharedDocumentsLocation {
    static var defaultURL: URL? {
        #if os(iOS)
        URL.documentsDirectory
        #else
        nil
        #endif
    }
}

// Tokens have a single MainActor owner. Destruction only happens once that owner is released.
private final class PlaybackResources: @unchecked Sendable {
    let player = AVPlayer()
    var timeObserver: Any?
    var notifications: [NSObjectProtocol] = []
    var remoteTargets: [(MPRemoteCommand, Any)] = []
    deinit {
        player.pause()
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        notifications.forEach { NotificationCenter.default.removeObserver($0) }
        remoteTargets.forEach { $0.0.removeTarget($0.1) }
    }
}
