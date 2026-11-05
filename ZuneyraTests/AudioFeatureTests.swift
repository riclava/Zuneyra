import AVFoundation
import Foundation
import Testing
@testable import Zuneyra

struct AudioFeatureTests {
    @Test func tenThousandTrackLibraryLoadAndSearchBudget() async throws {
        let root = URL.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = MusicRepository(root: root)
        for index in 0..<10_000 {
            try await repository.save(Track(id: UUID(), title: "Song \(index)", artist: "Artist \(index % 100)", album: "Album \(index / 10)", albumArtist: "Artist \(index % 100)", trackNumber: index % 10, duration: 180, filename: "\(index).wav", digest: "\(index)", artwork: nil, metadataRepairVersion: 1))
        }
        let clock = ContinuousClock()
        let start = clock.now
        let loaded = try await repository.load()
        let loadTime = start.duration(to: clock.now)
        let searchStart = clock.now
        let matches = loaded.filter { LibraryPresentation.matches($0, query: "Song 999") }
        let searchTime = searchStart.duration(to: clock.now)
        #expect(loaded.count == 10_000 && matches.count == 11)
        #expect(loadTime < .seconds(2))
        #expect(searchTime < .seconds(1))
        print("LIBRARY_BENCHMARK tracks=10000 load=\(loadTime) search=\(searchTime)")
    }

    @Test func gainProcessingChangesSamplesAndClampsClipping() throws {
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2))
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 3))
        buffer.frameLength = 3
        let channels = try #require(buffer.floatChannelData)
        for channel in 0..<2 { channels[channel][0] = 0.1; channels[channel][1] = 0.75; channels[channel][2] = -0.75 }
        processGainBuffers(buffer.mutableAudioBufferList, frameCount: 3, format: format.streamDescription.pointee, scale: 2)
        for channel in 0..<2 {
            #expect(abs(channels[channel][0] - 0.2) < 0.00001)
            #expect(channels[channel][1] == 1 && channels[channel][2] == -1)
        }
    }

    @Test func audioEngineContinuousSchedulingPrototype() throws {
        let engine = AVAudioEngine(), node = AVAudioPlayerNode()
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2))
        engine.attach(node); engine.connect(node, to: engine.mainMixerNode, format: format)
        try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 1024)
        defer { node.stop(); engine.stop() }
        for level: Float in [0.125, 0.25] {
            let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 512))
            buffer.frameLength = 512
            let channels = try #require(buffer.floatChannelData)
            for channel in 0..<2 { for sample in 0..<512 { channels[channel][sample] = level } }
            node.scheduleBuffer(buffer)
        }
        try engine.start(); node.play()
        let output = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1024))
        #expect(try engine.renderOffline(1024, to: output) == .success)
        #expect(output.frameLength == 1024)
        let samples = try #require(output.floatChannelData)[0]
        #expect(abs(samples[511] - 0.125) < 0.00001)
        #expect(abs(samples[512] - 0.25) < 0.00001)
    }

    @Test func englishCatalogIncludesPluralForms() throws {
        let location = try #require(Bundle.main.url(forResource: "en", withExtension: "lproj"))
        let english = try #require(Bundle(url: location))
        let count = 1, duration = "3 min"
        #expect(String(localized: "\(count) 首 · \(duration)", bundle: english, locale: Locale(identifier: "en")) == "1 song · 3 min")
        #expect(english.localizedString(forKey: "音乐库管理", value: nil, table: nil) == "Manage Library")
        #expect(english.localizedString(forKey: "导出音乐库备份…", value: nil, table: nil) == "Export Library Backup…")
    }

    @Test func replayGainConvertsDecibelsFallsBackAndLimitsPeaks() {
        var gain = ReplayGain(trackGain: -6, albumGain: -3, trackPeak: 0.8, albumPeak: 0.9)
        #expect(abs(gain.scale(for: .track) - 0.501187) < 0.00001)
        #expect(abs(gain.scale(for: .album) - 0.707946) < 0.00001)
        #expect(gain.scale(for: .off) == 1)
        gain.albumGain = nil
        #expect(gain.scale(for: .album) == gain.scale(for: .track))
        gain.trackGain = 12
        #expect(gain.scale(for: .track) == 1.25)
        gain.trackGain = .infinity
        #expect(gain.scale(for: .track) == 1)
    }

    @Test func generatedFormatsDecodeSeekAndImportMetadata() async throws {
        let root = URL.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = MusicRepository(root: root)
        let bundle = Bundle(for: BundleMarker.self)
        let all = (bundle.urls(forResourcesWithExtension: nil, subdirectory: "Formats") ?? [])
            + (bundle.urls(forResourcesWithExtension: nil, subdirectory: "Fixtures/Formats") ?? [])
        // Xcode's synchronized resource group may flatten the fixture files.
        let names = ["test.mp3", "test-aac.m4a", "test-alac.m4a", "test.flac", "test.wav", "test.aiff"]
        for name in names {
            let url = try #require(all.first { $0.lastPathComponent == name } ?? bundle.url(forResource: name, withExtension: nil))
            let asset = AVURLAsset(url: url)
            #expect(try await asset.load(.isPlayable))
            let audio = try AVAudioFile(forReading: url)
            let frame = AVAudioFramePosition(audio.processingFormat.sampleRate)
            audio.framePosition = frame
            let buffer = try #require(AVAudioPCMBuffer(pcmFormat: audio.processingFormat, frameCapacity: 256))
            try audio.read(into: buffer)
            #expect(buffer.frameLength == 256)
            #expect(audio.framePosition == frame + 256)
            let report = try await repository.importFiles([url]) { _, _ in }
            #expect(report.added == 1 && report.failures.isEmpty)
            if name == "test.flac" || name == "test.mp3" {
                let extended = try ExtendedMetadata(url: url)
                #expect(extended.replayGain.trackGain == -6)
            }
        }
        #expect(try await repository.load().count == 6)
        let flac = try #require(try await repository.load().first { $0.filename.hasSuffix(".flac") })
        #expect(flac.title == "Format Test" && flac.discNumber == 2 && flac.trackNumber == 2)
    }

    @Test @MainActor func gainTapAttachesToRealAudioItem() async throws {
        let bundle = Bundle(for: BundleMarker.self)
        let url = try #require(bundle.url(forResource: "test", withExtension: "wav", subdirectory: "Formats") ?? bundle.url(forResource: "test", withExtension: "wav"))
        let item = AVPlayerItem(url: url)
        try await applyReplayGain(to: item, metadata: ReplayGain(trackGain: 6, trackPeak: 0.1), mode: .track)
        #expect(item.audioMix?.inputParameters.first?.audioTapProcessor != nil)
        try await applyReplayGain(to: item, metadata: nil, mode: .off)
        #expect(item.audioMix == nil)
    }
}

private final class BundleMarker: NSObject {}
