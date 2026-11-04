#if DEBUG
import Foundation
import AVFoundation

/// Isolated, generated silent tracks for UI regression tests; never uses the user's library.
@MainActor enum UITestFixture {
    static var deviceCheck: Bool { ProcessInfo.processInfo.arguments.contains("--device-audio-check") }
    static var enabled: Bool { deviceCheck || ProcessInfo.processInfo.arguments.contains("--ui-test-playback") }
    static func makeStore() -> PlayerStore {
        let args = ProcessInfo.processInfo.arguments
        let session = args.firstIndex(of: "--ui-test-session").flatMap { index in args.indices.contains(index + 1) ? UUID(uuidString: args[index + 1])?.uuidString : nil }
        let id = deviceCheck ? "DeviceAudioCheck" : session ?? UUID().uuidString
        return PlayerStore(repository: MusicRepository(root: URL.temporaryDirectory.appending(path: "Zuneyra-UI-\(id)")), preferences: UserDefaults(suiteName: "Zuneyra-UI-\(id)")!, sharedDocumentsURL: nil)
    }
    static func seed(_ repository: MusicRepository) async throws {
        guard try await repository.load().isEmpty else { return }
        let format = AVAudioFormat(standardFormatWithSampleRate: 8000, channels: 1)!
        let duration: Double = deviceCheck ? 600 : 30
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(duration * 8000))!
        buffer.frameLength = buffer.frameCapacity
        memset(buffer.floatChannelData![0], 0, Int(buffer.frameLength) * MemoryLayout<Float>.size)
        if deviceCheck {
            for index in 0..<Int(buffer.frameLength) {
                let time = Double(index) / 8000
                let fade = min(1, time / 0.1, (duration - time) / 0.1)
                buffer.floatChannelData![0][index] = Float(0.035 * sin(2 * .pi * 330 * time) * fade)
            }
        }
        let titles = deviceCheck ? ["设备播放验收"] : ProcessInfo.processInfo.arguments.contains("--ui-test-queue") ? ["Search Regression", "Queue Second", "Queue Third"] : ["Search Regression"]
        for (index, title) in titles.enumerated().reversed() {
            let track = Track(id: UUID(), title: title, artist: "Generated Silence", album: "UI Fixture", albumArtist: "Generated Silence", trackNumber: index + 1, duration: duration, filename: "fixture-\(index).wav", digest: "ui-fixture-\(index)", artwork: nil, metadataRepairVersion: 1)
            let url = await repository.mediaURL(for: track)
            let file = try AVAudioFile(forWriting: url, settings: format.settings)
            try file.write(from: buffer)
            try await repository.save(track)
        }
        if ProcessInfo.processInfo.arguments.contains("--ui-test-carplay") {
            let songs = try await repository.load()
            if let first = songs.first { _ = try await repository.toggleFavorite(id: first.id) }
            _ = try await repository.createPlaylist(name: "车载测试歌单", trackIDs: songs.map(\.id))
            let missing = Track(id: UUID(), title: "不可用文件测试", artist: "Generated Fixture", album: "不可用文件测试", albumArtist: "Generated Fixture", trackNumber: 1, duration: 30, filename: "missing-validation.wav", digest: "missing-validation", artwork: nil, metadataRepairVersion: 1)
            try await repository.save(missing)
        }
    }
}
#endif
