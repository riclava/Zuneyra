import SwiftUI
import AVFoundation
import MediaPlayer
import Observation
import ImageIO
#if os(iOS)
import UIKit
#else
import AppKit
#endif

@MainActor @Observable
final class PlayerStore {
    var tracks: [Track] = [] {
        didSet { trackIndex = Dictionary(uniqueKeysWithValues: tracks.map { ($0.id, $0) }) }
    }
    @ObservationIgnored private var trackIndex: [UUID: Track] = [:]
    private(set) var playlists: [Playlist] = []
    private(set) var isEditingPlaylists = false
    var playlistNotice: String?
    var current: Track?
    var isPlaying = false
    var position = 0.0
    var isImporting = false
    var importProgress = ""
    var importReport: ImportReport?
    var errorMessage: String?
    var isLoading = true
    var isManaging = false
    var history: [ImportRecord] = []
    var storage: StorageUsage?
    var managementMessage: String?
    var isBusy: Bool { isLoading || isImporting || isManaging || isEditingPlaylists }
    var supportsIncomingFiles: Bool { sharedDocumentsURL != nil }
    private(set) var queueState = PlaybackQueue()
    var queueNotice: String?
    var queue: [Track] { queueState.orderedEntries.compactMap { track(for: $0) } }
    func track(for entry: QueueEntry) -> Track? {
        _ = tracks.count // Subscribe UI readers to library metadata changes.
        return trackIndex[entry.trackID]
    }
    let repository: MusicRepository
    private let preferences: UserDefaults
    private let sharedDocumentsURL: URL?
    private let resources = PlaybackResources()
    private var player: AVPlayer { resources.player }
    private var itemObservation: NSKeyValueObservation?
    private var rateObservation: NSKeyValueObservation?
    @ObservationIgnored private var artworkTask: Task<Void, Never>?
    private var artworkTrackID: UUID?
    private var nowPlayingArtwork: MPMediaItemArtwork?
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
                guard let self, !self.isPreparing, !self.isSeeking, self.player.currentItem != nil else { return }
                // A queued callback can contain a pre-seek time. Read the current
                // clock here so it cannot overwrite the restored/scrubbed position.
                let seconds = self.player.currentTime().seconds
                guard seconds.isFinite else { return }
                self.position = max(0, seconds)
                let checkpoint = Int(self.position) / 5
                if checkpoint != self.lastCheckpoint {
                    self.lastCheckpoint = checkpoint; self.saveSession()
                    #if DEBUG && os(iOS)
                    DevicePlaybackCheck.record("checkpoint", store: self)
                    #endif
                }
            }
        }
        rateObservation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isPlaying = self.player.timeControlStatus == .playing
                self.updateNowPlaying()
                #if DEBUG && os(iOS)
                DevicePlaybackCheck.record("playback-state", store: self)
                #endif
            }
        }
        resources.notifications.append(NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: nil, queue: .main) { [weak self] note in
            let finishedItem = note.object as? AVPlayerItem
            Task { @MainActor [weak self] in
                guard let self, self.wantsPlayback, let item = finishedItem, item === self.player.currentItem else { return }
                self.next(automatically: true)
            }
        })
        #if os(iOS)
        resources.notifications.append(NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] note in
            let reason = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            Task { @MainActor [weak self] in
                guard let self else { return }
                if reason == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue { self.pause() }
                #if DEBUG
                DevicePlaybackCheck.record("route-change-\(reason ?? 0)", store: self)
                #endif
            }
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
                #if DEBUG
                DevicePlaybackCheck.record("interruption-\(type ?? 0)", store: self)
                #endif
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
            playlists = try await repository.loadPlaylists()
            history = try await repository.importHistory()
            if let data = preferences.data(forKey: "playbackSession") {
                var savedPosition = 0.0
                if let saved = try? JSONDecoder().decode(PlaybackSnapshot.self, from: data), saved.version == 2 {
                    queueState = saved.queue
                    savedPosition = saved.position
                } else if let legacy = try? JSONDecoder().decode(LegacySession.self, from: data) {
                    let ids = legacy.queue.filter { trackIndex[$0] != nil }
                    queueState.replace(trackIDs: ids, selectedIndex: ids.firstIndex(of: legacy.current))
                    savedPosition = legacy.position
                }
                queueState.reconcile(validTrackIDs: Set(trackIndex.keys))
                if let entry = queueState.currentEntry, let track = track(for: entry) {
                    let request = beginTransition(autoplay: false)
                    current = track
                    await prepare(entry, request: request, offset: savedPosition, reportMissing: true)
                }
                saveSession()
            }
        } catch { errorMessage = error.localizedDescription }
        isLoading = false
        scanSharedDocuments()
    }

    func scanSharedDocuments() {
        guard !isLoading, !isImporting, !isManaging, !isEditingPlaylists, let sharedDocumentsURL else { return }
        isImporting = true
        importProgress = "正在检查电脑传入的音乐…"
        importTask = Task {
            do {
                let report = try await repository.importSharedDocuments(from: sharedDocumentsURL) { [weak self] completed, total in
                    await MainActor.run { [weak self] in self?.importProgress = "正在导入电脑音乐 \(completed) / \(total)" }
                }
                tracks = try await repository.load()
                history = try await repository.importHistory()
                if report.added > 0 || report.duplicates > 0 || !report.failures.isEmpty || report.cancelled { importReport = report }
            } catch is CancellationError { /* The next scan can retry unprocessed files. */ }
            catch { errorMessage = error.localizedDescription }
            isImporting = false
            importTask = nil
        }
    }

    func importFiles(_ urls: [URL]) {
        guard !isLoading, !isImporting, !isManaging, !isEditingPlaylists else { return }
        isImporting = true; importProgress = "正在准备文件…"
        importTask = Task {
            do {
                let report = try await repository.importFiles(urls) { [weak self] completed, total in
                    await MainActor.run { [weak self] in self?.importProgress = "正在导入 \(completed) / \(total)" }
                }
                tracks = try await repository.load()
                history = try await repository.importHistory()
                importReport = report
            } catch { errorMessage = error.localizedDescription }
            isImporting = false
            importTask = nil
        }
    }
    func retryImport(_ record: ImportRecord) {
        importFiles(record.report.failureItems.map { $0.resolvedURL() })
    }

    func refreshManagement() async {
        do {
            history = try await repository.importHistory()
            storage = try await repository.storageUsage(documents: sharedDocumentsURL)
        } catch { errorMessage = error.localizedDescription }
    }

    func deleteTracks(_ ids: Set<UUID>) async -> Bool {
        guard !isBusy, !ids.isEmpty else { return false }
        isManaging = true
        defer { isManaging = false }
        let deletingCurrent = (current.map { ids.contains($0.id) } ?? false) || (queueState.currentEntry.map { ids.contains($0.trackID) } ?? false)
        if deletingCurrent {
            generation += 1; seekRevision += 1; isPreparing = false; isSeeking = false
            pause()
        }
        do {
            let result = try await repository.deleteTracks(ids)
            tracks.removeAll { ids.contains($0.id) }
            queueState.removeTracks(ids)
            if deletingCurrent {
                player.replaceCurrentItem(with: nil)
                itemObservation = nil
                current = nil; position = 0
                MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
                #if os(macOS)
                MPNowPlayingInfoCenter.default().playbackState = .stopped
                #endif
            }
            saveSession()
            playlists = try await repository.loadPlaylists()
            managementMessage = "已从音乐库删除 \(result.removed) 首歌曲，清除约 \(StorageUsage.formatted(result.bytes)) 的副本。Finder 或其他原位置文件保留。" + (result.failures.isEmpty ? "" : "\n" + result.failures.joined(separator: "\n"))
            await refreshManagement()
            return true
        } catch { errorMessage = error.localizedDescription; return false }
    }

    func cleanIncomingFiles() async {
        guard !isBusy, let sharedDocumentsURL else { return }
        isManaging = true
        defer { isManaging = false }
        do {
            let result = try await repository.cleanImportedDocuments(sharedDocumentsURL)
            managementMessage = result.message
            await refreshManagement()
        } catch { errorMessage = error.localizedDescription }
    }

    func clearArtwork() async {
        guard !isBusy else { return }
        isManaging = true
        defer { isManaging = false }
        do {
            let result = try await repository.clearArtworkCache()
            managementMessage = result.message + "封面将在浏览时按需重新生成。"
            await refreshManagement()
        } catch { errorMessage = error.localizedDescription }
    }

    func cancelImport() { importTask?.cancel() }

    func playlistTracks(_ id: UUID) -> [Track] {
        _ = tracks.count
        return playlists.first { $0.id == id }?.trackIDs.compactMap { trackIndex[$0] } ?? []
    }
    private func modifyPlaylists<T>(_ change: (MusicRepository) async throws -> T) async throws -> T {
        guard !isBusy else { throw NSError(domain: "Zuneyra.Playlist", code: 1, userInfo: [NSLocalizedDescriptionKey: "正在处理音乐库，请稍后重试"]) }
        isEditingPlaylists = true
        defer { isEditingPlaylists = false }
        let result = try await change(repository)
        playlists = try await repository.loadPlaylists()
        return result
    }
    func createPlaylist(name: String, tracks: [Track] = []) async throws -> Playlist {
        try await modifyPlaylists { try await $0.createPlaylist(name: name, trackIDs: tracks.map(\.id)) }
    }
    func renamePlaylist(_ id: UUID, name: String) async throws {
        try await modifyPlaylists { try await $0.renamePlaylist(id, name: name) }
    }
    func deletePlaylist(_ id: UUID) async throws {
        try await modifyPlaylists { try await $0.deletePlaylist(id) }
    }
    func addToPlaylist(_ id: UUID, tracks: [Track]) async throws {
        try await modifyPlaylists { try await $0.addToPlaylist(id, trackIDs: tracks.map(\.id)) }
    }
    func removeFromPlaylist(_ id: UUID, trackIDs: Set<UUID>) async throws {
        try await modifyPlaylists { try await $0.removeFromPlaylist(id, trackIDs: trackIDs) }
    }
    func movePlaylistTracks(_ id: UUID, from offsets: IndexSet, to destination: Int) async throws {
        try await modifyPlaylists { try await $0.movePlaylistTracks(id, from: offsets, to: destination) }
    }
    func playPlaylist(_ id: UUID, shuffled: Bool = false, startingAt trackID: UUID? = nil) {
        let ordered = playlistTracks(id)
        guard !isManaging, let first = trackID.flatMap({ id in ordered.first { $0.id == id } }) ?? (shuffled ? ordered.randomElement() : ordered.first) else { return }
        queueState.setShuffle(shuffled)
        play(first, context: ordered)
    }

    func play(_ track: Track, context: [Track]) {
        guard !isManaging, trackIndex[track.id] != nil else { return }
        var ids = context.map(\.id).filter { trackIndex[$0] != nil }
        if !ids.contains(track.id) { ids = [track.id] }
        queueState.replace(trackIDs: ids, selectedIndex: ids.firstIndex(of: track.id))
        if let entry = queueState.currentEntry { schedule(entry) }
    }
    func playQueueEntry(_ id: UUID) {
        guard !isManaging else { return }
        if id == queueState.currentID, player.currentItem != nil { resume(); return }
        guard let entry = queueState.select(id) else { return }
        schedule(entry)
    }
    func insertNext(_ additions: [Track]) {
        guard !isManaging else { return }
        queueState.insertNext(trackIDs: additions.map(\.id).filter { trackIndex[$0] != nil })
        saveSession()
    }
    func appendToQueue(_ additions: [Track]) {
        guard !isManaging else { return }
        queueState.append(trackIDs: additions.map(\.id).filter { trackIndex[$0] != nil })
        saveSession()
    }
    func removeQueueEntry(_ id: UUID) {
        guard !isManaging else { return }
        let removingCurrent = id == queueState.currentID
        queueState.remove([id])
        if removingCurrent { stopPlayback() }
        saveSession()
    }
    func clearUpcoming() {
        guard !isManaging else { return }
        queueState.clearUpcoming()
        saveSession()
    }
    func moveUpcoming(from offsets: IndexSet, to destination: Int) {
        guard !isManaging else { return }
        queueState.moveUpcoming(from: offsets, to: destination)
        saveSession()
    }
    func moveUpcomingEntry(_ id: UUID, direction: Int) {
        guard let index = queueState.upcoming.firstIndex(of: id) else { return }
        let target = index + direction
        guard queueState.upcoming.indices.contains(target) else { return }
        moveUpcoming(from: IndexSet(integer: index), to: direction > 0 ? target + 1 : target)
    }
    func toggleShuffle() { setShuffle(!queueState.shuffle) }
    func setShuffle(_ enabled: Bool) {
        guard !isManaging else { return }
        queueState.setShuffle(enabled)
        saveSession(); updateNowPlaying()
    }
    func cycleRepeatMode() { setRepeatMode(queueState.repeatMode.next) }
    func setRepeatMode(_ mode: QueueRepeatMode) {
        guard !isManaging else { return }
        queueState.setRepeat(mode)
        saveSession(); updateNowPlaying()
    }
    @discardableResult func performCarPlayAction(_ action: CarPlayAction) -> Bool {
        guard !isLoading, !isManaging else { return false }
        let catalog = CarPlayCatalog(tracks: tracks, playlists: playlists, queue: queueState)
        switch action {
        case .play(let id, let route):
            let songs = catalog.tracks(for: route)
            guard let chosen = songs.first(where: { $0.id == id }) else { return carPlayContentUnavailable() }
            setShuffle(false); play(chosen, context: songs)
        case .playAll(let route, let shuffled):
            let songs = catalog.tracks(for: route)
            guard let chosen = shuffled ? songs.randomElement() : songs.first else { return carPlayContentUnavailable() }
            setShuffle(shuffled); play(chosen, context: songs)
        case .queueEntry(let id):
            guard queueState.canonical.contains(where: { $0.id == id }) else { return carPlayContentUnavailable() }
            playQueueEntry(id)
        case .open: return false
        }
        return true
    }
    private func carPlayContentUnavailable() -> Bool {
        errorMessage = "这些歌曲已从音乐库或歌单中移除，请返回列表重新选择。"
        return false
    }
    private func beginTransition(autoplay: Bool) -> Int {
        generation += 1
        seekRevision += 1
        isPreparing = true; isSeeking = false
        wantsPlayback = autoplay
        queueNotice = nil
        itemObservation = nil
        player.pause()
        player.replaceCurrentItem(with: nil)
        isPlaying = false
        return generation
    }
    private func schedule(_ entry: QueueEntry, offset: Double = 0) {
        let request = beginTransition(autoplay: true)
        current = track(for: entry); position = offset
        saveSession()
        Task { await prepare(entry, request: request, offset: offset, reportMissing: true) }
    }
    @discardableResult
    private func prepare(_ entry: QueueEntry, request: Int, offset: Double = 0, reportMissing: Bool) async -> Bool {
        guard request == generation, queueState.currentID == entry.id,
              let track = track(for: entry) else { return false }
        current = track
        position = min(max(0, offset.isFinite ? offset : 0), track.duration)
        let url = await repository.mediaURL(for: track)
        guard request == generation, queueState.currentID == entry.id else { return false }
        guard FileManager.default.fileExists(atPath: url.path) else {
            if reportMissing {
                isPreparing = false; wantsPlayback = false
                errorMessage = "找不到「\(track.title)」的本地文件。可以重新连接来源或导入音乐后重试。"
                saveSession(); updateNowPlaying()
            }
            return false
        }
        let item = AVPlayerItem(url: url)
        itemObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            guard item.status == .failed else { return }
            let message = item.error?.localizedDescription ?? "无法播放此音频"
            Task { @MainActor [weak self] in
                guard let self, request == self.generation else { return }
                self.isPreparing = false
                self.pause(); self.errorMessage = message
            }
        }
        player.replaceCurrentItem(with: item)
        if position > 0 { await player.seek(to: CMTime(seconds: position, preferredTimescale: 600)) }
        guard request == generation, queueState.currentID == entry.id else { return false }
        isPreparing = false
        if wantsPlayback { resume() }
        saveSession(); updateNowPlaying()
        return true
    }
    private func stopPlayback() {
        generation += 1; seekRevision += 1
        isPreparing = false; isSeeking = false; wantsPlayback = false
        player.pause(); player.replaceCurrentItem(with: nil)
        itemObservation = nil
        current = nil; position = 0; isPlaying = false
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        #if os(macOS)
        MPNowPlayingInfoCenter.default().playbackState = .stopped
        #endif
    }
    func toggle() {
        if isPlaying || (isPreparing && wantsPlayback) || player.timeControlStatus == .waitingToPlayAtSpecifiedRate { pause() }
        else { resume() }
    }
    func resume() {
        guard !isManaging else { return }
        wantsPlayback = true
        guard !isPreparing else { return }
        guard let entry = queueState.currentEntry else {
            if !queueState.upcoming.isEmpty { next() }
            else if let first = queueState.orderedEntries.first { playQueueEntry(first.id) }
            return
        }
        guard player.currentItem != nil else { schedule(entry, offset: position); return }
        do {
            #if os(iOS)
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
            #endif
            if position >= (current?.duration ?? 0) { seek(to: 0) }
            player.play()
        } catch { errorMessage = error.localizedDescription }
    }
    func pause() {
        wantsPlayback = false; resumeAfterInterruption = false; player.pause(); isPlaying = false; saveSession(); updateNowPlaying()
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
        #if DEBUG && os(iOS)
        DevicePlaybackCheck.record("pause", store: self)
        #endif
    }
    func seek(to seconds: Double) {
        guard let current, seconds.isFinite, player.currentItem != nil else { return }
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
        guard !isManaging else { return }
        let request = beginTransition(autoplay: true)
        // Advance synchronously so consecutive skip commands each select an entry.
        let first = queueState.advance(naturally: automatically)
        if let first { current = track(for: first); position = 0; saveSession() }
        Task {
            var candidate = first
            var attempted = Set<UUID>()
            let limit = queueState.canonical.count
            var traversals = 0
            while request == generation, attempted.count < limit, traversals < max(1, limit * 2), let entry = candidate {
                traversals += 1
                if attempted.insert(entry.id).inserted {
                    if await prepare(entry, request: request, reportMissing: false) {
                        if attempted.count > 1 { queueNotice = "已跳过 \(attempted.count - 1) 个不可用的本地文件。" }
                        return
                    }
                }
                guard request == generation else { return }
                guard attempted.count < limit else { break }
                // A missing repeat-one item must not retry itself forever.
                candidate = queueState.advance(naturally: false)
            }
            guard request == generation else { return }
            isPreparing = false
            if let entry = queueState.currentEntry { current = track(for: entry) }
            pause()
            if attempted.isEmpty {
                if automatically { position = current?.duration ?? 0 }
            } else {
                position = 0
                errorMessage = "队列中接下来的本地文件均不可用，播放已停止。"
            }
            saveSession(); updateNowPlaying()
        }
    }
    func previous() {
        guard !isManaging else { return }
        if position > 3 { seek(to: 0); return }
        let previousID = queueState.currentID
        guard let entry = queueState.previous() else { return }
        if entry.id == previousID, player.currentItem != nil { seek(to: 0) }
        else { schedule(entry) }
    }
    func toggleFavorite(_ track: Track) {
        guard !isManaging else { return }
        Task {
            do {
                guard let updated = try await repository.toggleFavorite(id: track.id) else { return }
                if let index = tracks.firstIndex(where: { $0.id == track.id }) { tracks[index] = updated }
                if current?.id == track.id { current = updated }
            } catch { errorMessage = error.localizedDescription }
        }
    }
    private struct LegacySession: Codable { let current: UUID; let queue: [UUID]; let position: Double }
    func saveSession() {
        guard !queueState.canonical.isEmpty || queueState.shuffle || queueState.repeatMode != .off else {
            preferences.removeObject(forKey: "playbackSession")
            return
        }
        let snapshot = PlaybackSnapshot(queue: queueState, position: queueState.currentID == nil ? 0 : position)
        if let data = try? JSONEncoder().encode(snapshot) { preferences.set(data, forKey: "playbackSession") }
    }
    private func updateNowPlaying() {
        guard let current else { return }
        if artworkTrackID != current.id {
            artworkTrackID = current.id; nowPlayingArtwork = nil; artworkTask?.cancel()
            artworkTask = Task { [weak self, repository] in
                guard let data = try? await repository.artworkData(for: current), !Task.isCancelled,
                      let source = CGImageSourceCreateWithData(data as CFData, nil),
                      let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 600] as CFDictionary),
                      let self, self.current?.id == current.id else { return }
                #if os(iOS)
                let image = UIImage(cgImage: cg)
                #else
                let image = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
                #endif
                self.nowPlayingArtwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
                self.updateNowPlaying()
            }
        }
        var info: [String: Any] = [MPMediaItemPropertyTitle: current.title, MPMediaItemPropertyArtist: current.artist, MPMediaItemPropertyAlbumTitle: current.album, MPMediaItemPropertyPlaybackDuration: current.duration, MPNowPlayingInfoPropertyElapsedPlaybackTime: position, MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0]
        if let nowPlayingArtwork { info[MPMediaItemPropertyArtwork] = nowPlayingArtwork }
        info[MPNowPlayingInfoPropertyPlaybackQueueCount] = queueState.canonical.count
        info[MPNowPlayingInfoPropertyPlaybackQueueIndex] = queueState.orderedEntries.firstIndex { $0.id == queueState.currentID } ?? 0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        let center = MPRemoteCommandCenter.shared()
        center.changeShuffleModeCommand.currentShuffleType = queueState.shuffle ? .items : .off
        center.changeRepeatModeCommand.currentRepeatType = switch queueState.repeatMode { case .off: .off; case .all: .all; case .one: .one }
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
        center.changeShuffleModeCommand.isEnabled = true
        center.changeRepeatModeCommand.isEnabled = true
        let shuffleToken = center.changeShuffleModeCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangeShuffleModeCommandEvent else { return .commandFailed }
            let enabled = event.shuffleType != .off
            Task { @MainActor [weak self] in self?.setShuffle(enabled) }; return .success
        }
        resources.remoteTargets.append((center.changeShuffleModeCommand, shuffleToken))
        let repeatToken = center.changeRepeatModeCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangeRepeatModeCommandEvent else { return .commandFailed }
            let mode: QueueRepeatMode = switch event.repeatType { case .one: .one; case .all: .all; default: .off }
            Task { @MainActor [weak self] in self?.setRepeatMode(mode) }; return .success
        }
        resources.remoteTargets.append((center.changeRepeatModeCommand, repeatToken))
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
