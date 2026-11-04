import Foundation
import Testing
@testable import Zuneyra

struct ZuneyraTests {
    private func fixture() throws -> (URL, URL) {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let source = root.appending(path: "Quiet Test.wav")
        // One second of 8 kHz mono 16-bit PCM silence, entirely generated for tests.
        var data = Data()
        func text(_ s: String) { data.append(contentsOf: s.utf8) }
        func u32(_ x: UInt32) { var value = x.littleEndian; withUnsafeBytes(of: &value) { data.append(contentsOf: $0) } }
        func u16(_ x: UInt16) { var value = x.littleEndian; withUnsafeBytes(of: &value) { data.append(contentsOf: $0) } }
        text("RIFF"); u32(16036); text("WAVEfmt "); u32(16); u16(1); u16(1); u32(8000); u32(16000); u16(2); u16(16); text("data"); u32(16000); data.append(Data(repeating: 0, count: 16000))
        try data.write(to: source)
        return (root, source)
    }

    @Test func importDeduplicatesAndPersistsManagedCopy() async throws {
        let (root, source) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let location = root.appending(path: "Library")
        let repository = MusicRepository(root: location)
        let report = try await repository.importFiles([source, source]) { _, _ in }
        #expect(report.added == 1)
        #expect(report.duplicates == 1)
        #expect(report.failures.isEmpty)
        var track = try #require(try await repository.load().first)
        #expect(track.title == "Quiet Test")
        #expect(abs(track.duration - 1) < 0.01)
        track.favorite = true
        try await repository.save(track)
        try FileManager.default.removeItem(at: source)
        let reopened = MusicRepository(root: location)
        let restored = try await reopened.load()
        #expect(restored.count == 1)
        #expect(restored.first?.favorite == true)
        #expect(restored.first?.id == track.id)
        let managed = await reopened.mediaURL(for: track)
        #expect(FileManager.default.fileExists(atPath: managed.path))
    }

    @Test func damagedAudioDoesNotBlockOtherFiles() async throws {
        let (root, source) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let broken = root.appending(path: "broken.mp3")
        try Data("not audio".utf8).write(to: broken)
        let repository = MusicRepository(root: root.appending(path: "Library"))
        let report = try await repository.importFiles([broken, source]) { _, _ in }
        #expect(report.failures.count == 1)
        #expect(report.added == 1)
        #expect(try await repository.load().count == 1)
        let staging = root.appending(path: "Library/Staging")
        #expect(try FileManager.default.contentsOfDirectory(atPath: staging.path).isEmpty)
    }

    @Test func folderImportAndRenamedDuplicate() async throws {
        let (root, source) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appending(path: "Album")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: source, to: folder.appending(path: "Renamed.wav"))
        let repository = MusicRepository(root: root.appending(path: "Library"))
        _ = try await repository.importFiles([source]) { _, _ in }
        let report = try await repository.importFiles([folder]) { _, _ in }
        #expect(report.duplicates == 1)
        #expect(try await repository.load().count == 1)
    }
    @Test @MainActor func playbackQueueSeekAndPausedRestoration() async throws {
        let (root, source) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let second = root.appending(path: "Second.wav")
        var audio = try Data(contentsOf: source); audio[audio.count - 1] = 1
        try audio.write(to: second)
        let repository = MusicRepository(root: root.appending(path: "Library"))
        _ = try await repository.importFiles([source, second]) { _, _ in }
        let suite = UUID().uuidString
        let preferences = try #require(UserDefaults(suiteName: suite))
        defer { preferences.removePersistentDomain(forName: suite) }
        let store = PlayerStore(repository: repository, preferences: preferences)
        await store.load()
        let first = try #require(store.tracks.first)
        store.play(first, context: store.tracks)
        // Simulator audio startup varies; assert actual readiness with a bounded wait.
        for _ in 0..<100 {
            if store.isPlaying || store.errorMessage != nil { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(store.isPlaying)
        store.pause()
        #expect(store.errorMessage == nil)
        #expect(store.current?.id == first.id)
        store.seek(to: 0.4)
        #expect(store.position == 0.4)
        let restored = PlayerStore(repository: repository, preferences: preferences)
        await restored.load()
        #expect(restored.current?.id == first.id)
        #expect(abs(restored.position - 0.4) < 0.05)
        #expect(!restored.isPlaying)
        store.next()
        try await Task.sleep(for: .milliseconds(200))
        store.pause()
        #expect(store.current?.id == store.tracks.last?.id)
        #expect(store.errorMessage == nil)
    }

}
