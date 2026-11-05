import Foundation
import AVFoundation
import MediaToolbox

enum ReplayGainMode: String, CaseIterable, Identifiable {
    case off, track, album
    var id: String { rawValue }
    var shortTitle: String { switch self { case .off: String(localized: "关闭"); case .track: String(localized: "曲目"); case .album: String(localized: "专辑") } }
    var title: String { switch self { case .off: String(localized: "关闭增益"); case .track: String(localized: "曲目增益"); case .album: String(localized: "专辑增益") } }
}

struct ReplayGain: Codable, Hashable, Sendable {
    var trackGain: Double?
    var albumGain: Double?
    var trackPeak: Double?
    var albumPeak: Double?

    func scale(for mode: ReplayGainMode) -> Double {
        guard mode != .off else { return 1 }
        let album = mode == .album && albumGain != nil
        guard let gain = album ? albumGain : trackGain, gain.isFinite, (-60...30).contains(gain) else { return 1 }
        var scale = pow(10, gain / 20)
        if let peak = album ? albumPeak : trackPeak, peak.isFinite, peak > 0 { scale = min(scale, 1 / peak) }
        return scale
    }
    mutating func set(_ key: String, value: String) {
        guard let token = value.trimmingCharacters(in: .whitespacesAndNewlines).split(whereSeparator: { $0.isWhitespace }).first,
              let number = Double(token), number.isFinite else { return }
        switch key.uppercased() {
        case "REPLAYGAIN_TRACK_GAIN": trackGain = number
        case "REPLAYGAIN_ALBUM_GAIN": albumGain = number
        case "REPLAYGAIN_TRACK_PEAK": trackPeak = number
        case "REPLAYGAIN_ALBUM_PEAK": albumPeak = number
        default: break
        }
    }
}

// Storage is immutable during rendering except for format set by the serial prepare callback.
// The render callback allocates no buffers, performs no I/O, and acquires no locks.
private struct GainTapState {
    let scale: Double
    var format = AudioStreamBasicDescription()
}

nonisolated private func gainTapInit(_ tap: MTAudioProcessingTap, _ info: UnsafeMutableRawPointer?, _ storage: UnsafeMutablePointer<UnsafeMutableRawPointer?>) { storage.pointee = info }
nonisolated private func gainTapFinalize(_ tap: MTAudioProcessingTap) {
    let state = MTAudioProcessingTapGetStorage(tap).assumingMemoryBound(to: GainTapState.self)
    state.deinitialize(count: 1); state.deallocate()
}
nonisolated private func gainTapPrepare(_ tap: MTAudioProcessingTap, _ frames: CMItemCount, _ format: UnsafePointer<AudioStreamBasicDescription>) {
    MTAudioProcessingTapGetStorage(tap).assumingMemoryBound(to: GainTapState.self).pointee.format = format.pointee
}
nonisolated private func gainTapUnprepare(_ tap: MTAudioProcessingTap) {}
nonisolated private func gainTapProcess(_ tap: MTAudioProcessingTap, _ frames: CMItemCount, _ flags: MTAudioProcessingTapFlags, _ buffers: UnsafeMutablePointer<AudioBufferList>, _ outFrames: UnsafeMutablePointer<CMItemCount>, _ outFlags: UnsafeMutablePointer<MTAudioProcessingTapFlags>) {
    let status = MTAudioProcessingTapGetSourceAudio(tap, frames, buffers, outFlags, nil, outFrames)
    guard status == noErr else { outFrames.pointee = 0; return }
    let state = MTAudioProcessingTapGetStorage(tap).assumingMemoryBound(to: GainTapState.self).pointee
    processGainBuffers(buffers, frameCount: outFrames.pointee, format: state.format, scale: state.scale)
}

nonisolated func processGainBuffers(_ buffers: UnsafeMutablePointer<AudioBufferList>, frameCount: CMItemCount, format: AudioStreamBasicDescription, scale: Double) {
    guard format.mFormatID == kAudioFormatLinearPCM,
          format.mFormatFlags & kAudioFormatFlagIsBigEndian == 0 else { return }
    for buffer in UnsafeMutableAudioBufferListPointer(buffers) {
        guard let data = buffer.mData else { continue }
        let samples = min(Int(buffer.mDataByteSize) / max(1, Int(format.mBitsPerChannel / 8)), Int(frameCount) * Int(buffer.mNumberChannels))
        if format.mFormatFlags & kAudioFormatFlagIsFloat != 0, format.mBitsPerChannel == 32 {
            let values = data.assumingMemoryBound(to: Float.self)
            for i in 0..<samples { values[i] = Float(max(-1, min(1, Double(values[i]) * scale))) }
        } else if format.mFormatFlags & kAudioFormatFlagIsFloat != 0, format.mBitsPerChannel == 64 {
            let values = data.assumingMemoryBound(to: Double.self)
            for i in 0..<samples { values[i] = max(-1, min(1, values[i] * scale)) }
        } else if format.mFormatFlags & kAudioFormatFlagIsSignedInteger != 0, format.mBitsPerChannel == 16 {
            let values = data.assumingMemoryBound(to: Int16.self)
            for i in 0..<samples { values[i] = Int16(max(-32768, min(32767, Double(values[i]) * scale))) }
        } else if format.mFormatFlags & kAudioFormatFlagIsSignedInteger != 0, format.mBitsPerChannel == 32 {
            let values = data.assumingMemoryBound(to: Int32.self)
            for i in 0..<samples { values[i] = Int32(max(Double(Int32.min), min(Double(Int32.max), Double(values[i]) * scale))) }
        }
    }
}

@MainActor
func applyReplayGain(to item: AVPlayerItem, metadata: ReplayGain?, mode: ReplayGainMode) async throws {
    let scale = metadata?.scale(for: mode) ?? 1
    guard scale != 1 else { item.audioMix = nil; return }
    let tracks = try await item.asset.loadTracks(withMediaType: .audio)
    let mix = AVMutableAudioMix()
    mix.inputParameters = try tracks.map { track in
        let state = UnsafeMutablePointer<GainTapState>.allocate(capacity: 1)
        state.initialize(to: GainTapState(scale: scale))
        var callbacks = MTAudioProcessingTapCallbacks(version: kMTAudioProcessingTapCallbacksVersion_0, clientInfo: state,
            init: gainTapInit, finalize: gainTapFinalize, prepare: gainTapPrepare, unprepare: gainTapUnprepare, process: gainTapProcess)
        var created: MTAudioProcessingTap?
        let status = MTAudioProcessingTapCreate(kCFAllocatorDefault, &callbacks, kMTAudioProcessingTapCreationFlag_PreEffects, &created)
        guard status == noErr, let tap = created else {
            state.deinitialize(count: 1); state.deallocate()
            throw NSError(domain: "Zuneyra.Audio", code: Int(status), userInfo: [NSLocalizedDescriptionKey: String(localized: "无法启用音量增益处理")])
        }
        let parameter = AVMutableAudioMixInputParameters(track: track)
        parameter.audioTapProcessor = tap
        return parameter
    }
    try Task.checkCancellation()
    item.audioMix = mix
}
