#if DEBUG && os(iOS)
import Foundation
import AVFoundation

/// Opt-in, generated-audio acceptance run. No log is written for normal libraries.
@MainActor enum DevicePlaybackCheck {
    struct Event: Codable {
        let time: Date
        let event: String
        let position: Double
        let playing: Bool
        let outputs: [String]
    }
    private static var events: [Event] = []
    static func record(_ event: String, store: PlayerStore) {
        guard UITestFixture.deviceCheck else { return }
        events.append(Event(time: Date(), event: event, position: store.position, playing: store.isPlaying,
                            outputs: AVAudioSession.sharedInstance().currentRoute.outputs.map { "\($0.portType.rawValue): \($0.portName)" }))
        events = Array(events.suffix(300))
        let location = URL.applicationSupportDirectory.appending(path: "device-playback-check.json")
        do {
            try FileManager.default.createDirectory(at: location.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(events).write(to: location, options: .atomic)
        } catch { /* Acceptance logging must not affect playback. */ }
    }
}
#endif
