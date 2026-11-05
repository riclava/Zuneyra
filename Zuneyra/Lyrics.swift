import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct LyricLine: Identifiable, Equatable {
    let id: Int
    let time: Double
    let text: String
}

struct Lyrics {
    let lines: [LyricLine]
    let plainText: String

    init(_ text: String) {
        plainText = text
        let pattern = #"\[(\d+):(\d{1,2}(?:\.\d+)?)\]"#
        let regex = try! NSRegularExpression(pattern: pattern)
        let offsetRegex = try! NSRegularExpression(pattern: #"\[offset:([+-]?\d+)\]"#, options: .caseInsensitive)
        let range = NSRange(text.startIndex..., in: text)
        let offset = offsetRegex.firstMatch(in: text, range: range).flatMap { Range($0.range(at: 1), in: text) }.flatMap { Double(text[$0]) }.map { $0 / 1000 } ?? 0
        var parsed: [(Double, String)] = []
        for raw in text.components(separatedBy: .newlines) {
            let matches = regex.matches(in: raw, range: NSRange(raw.startIndex..., in: raw))
            guard let last = matches.last, let end = Range(last.range, in: raw)?.upperBound else { continue }
            let content = String(raw[end...]).trimmingCharacters(in: .whitespaces)
            for match in matches {
                guard let minutes = Range(match.range(at: 1), in: raw), let seconds = Range(match.range(at: 2), in: raw),
                      let m = Double(raw[minutes]), let s = Double(raw[seconds]), s < 60 else { continue }
                parsed.append((max(0, m * 60 + s + offset), content))
            }
        }
        lines = parsed.enumerated().sorted { $0.element.0 == $1.element.0 ? $0.offset < $1.offset : $0.element.0 < $1.element.0 }
            .enumerated().map { LyricLine(id: $0.offset, time: $0.element.element.0, text: $0.element.element.1) }
    }
    func activeLine(at time: Double) -> Int? { lines.last(where: { $0.time <= time })?.id }
}

struct LyricsView: View {
    var embedded = false
    @Environment(PlayerStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @State private var choosingLyrics = false
    @State private var problem: String?
    @State private var lyrics = Lyrics("")

    var body: some View {
        let active = lyrics.activeLine(at: store.position)
        VStack(spacing: 0) {
            CollectionSheetHeader(title: String(localized: "歌词"), back: embedded ? nil : { dismiss() })
            Button(String(localized: "导入歌词…")) { choosingLyrics = true }
                .disabled(store.current == nil || store.isBusy).padding(.bottom, 12)
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        if lyrics.plainText.isEmpty {
                            Text(String(localized: "暂无歌词，可导入本地 LRC 或文本歌词。")).foregroundStyle(.secondary)
                        } else if lyrics.lines.isEmpty {
                            Text(lyrics.plainText).textSelection(.enabled)
                        } else {
                            ForEach(lyrics.lines) { line in
                                Button { store.seek(to: line.time) } label: {
                                    Text(line.text.isEmpty ? "♪" : line.text)
                                        .font(.title3).fontWeight(active == line.id ? .bold : .regular)
                                        .foregroundStyle(active == line.id ? Color.accentColor : .secondary)
                                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                }.buttonStyle(.plain).id(line.id)
                            }
                        }
                    }.padding(24)
                }
                .onChange(of: active) { _, id in if let id { proxy.scrollTo(id, anchor: .center) } }
            }
        }
        .task(id: store.current?.lyrics) { lyrics = Lyrics(store.current?.lyrics ?? "") }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Sunset.background(scheme).ignoresSafeArea())
        .collectionSheetChrome()
        .fileImporter(isPresented: $choosingLyrics, allowedContentTypes: [.plainText, .data]) { result in
            guard let id = store.current?.id else { return }
            switch result {
            case .success(let url): Task {
                do {
                    let updated = try await store.repository.importLyrics(from: url, trackID: id)
                    if let index = store.tracks.firstIndex(where: { $0.id == id }) { store.tracks[index] = updated }
                    if store.current?.id == id { store.current = updated }
                } catch { problem = error.localizedDescription }
            }
            case .failure(let error): problem = error.localizedDescription
            }
        }
        .alert(String(localized: "无法导入歌词"), isPresented: Binding(get: { problem != nil }, set: { if !$0 { problem = nil } })) {
            Button(String(localized: "好")) { problem = nil }
        } message: { Text(problem ?? "") }
    }
}
