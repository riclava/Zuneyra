#if DEBUG
import Foundation
import AVFoundation

/// An isolated, generated silent track for UI regression tests; never uses the user's library.
@MainActor enum UITestFixture {
    static var enabled: Bool { ProcessInfo.processInfo.arguments.contains("--ui-test-playback") }
    static func makeStore() -> PlayerStore {
        let id = UUID().uuidString
        return PlayerStore(repository: MusicRepository(root: URL.temporaryDirectory.appending(path: "Zuneyra-UI-\(id)")), preferences: UserDefaults(suiteName: "Zuneyra-UI-\(id)")!, sharedDocumentsURL: nil)
    }
    static func seed(_ repository: MusicRepository) async throws {
        _ = try await repository.load()
        let track = Track(id: UUID(), title: "Search Regression", artist: "Generated Silence", album: "UI Fixture", albumArtist: "Generated Silence", trackNumber: 1, duration: 30, filename: "fixture.wav", digest: "ui-fixture", artwork: nil, metadataRepairVersion: 1)
        let url = await repository.mediaURL(for: track)
        let format = AVAudioFormat(standardFormatWithSampleRate: 8000, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 240000)!
        buffer.frameLength = buffer.frameCapacity
        memset(buffer.floatChannelData![0], 0, Int(buffer.frameLength) * MemoryLayout<Float>.size)
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
        try await repository.save(track)
    }
}
#endif
