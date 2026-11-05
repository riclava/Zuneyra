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
    let returnToCover: () -> Void
    @Environment(PlayerStore.self) private var store
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var choosingLyrics = false
    @State private var importTrackID: UUID?
    @State private var problem: String?
    @State private var lyrics = Lyrics("")
    @State private var followsPlayback = true
    @State private var selectedLine: LyricLine?

    private struct ContentKey: Hashable {
        let trackID: UUID?
        let text: String
    }
    private var contentKey: ContentKey {
        ContentKey(trackID: store.current?.id, text: store.current?.lyrics ?? "")
    }

    var body: some View {
        let active = lyrics.activeLine(at: store.position)
        VStack(spacing: 0) {
            header
            ScrollViewReader { proxy in
                VStack(spacing: 0) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            if lyrics.plainText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                VStack(spacing: 8) {
                                    Image(systemName: "quote.bubble").font(.title2)
                                    Text(String(localized: "暂无歌词，可导入本地 LRC 或文本歌词。"))
                                        .font(.subheadline).multilineTextAlignment(.center)
                                    Button(String(localized: "导入歌词…"), action: beginImport)
                                        .frame(minHeight: 44)
                                        .disabled(store.current == nil || store.isBusy)
                                }
                                .foregroundStyle(Sunset.secondary(scheme))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                            } else if lyrics.lines.isEmpty {
                                Text(lyrics.plainText)
                                    .font(.title3).lineSpacing(10)
                            } else {
                                ForEach(lyrics.lines) { line in
                                    HStack(spacing: 4) {
                                        Text(line.text.isEmpty ? "♪" : line.text)
                                            .font(.title3).fontWeight(active == line.id ? .bold : .regular)
                                            .foregroundStyle(active == line.id ? Sunset.accent(scheme) : Sunset.secondary(scheme))
                                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                        Button {
                                            selectedLine = line
                                            followsPlayback = false
                                        } label: {
                                            Image(systemName: "play.circle")
                                                .font(.body)
                                                .frame(width: 44, height: 44)
                                        }
                                        .buttonStyle(.plain)
                                        .foregroundStyle(Sunset.secondary(scheme))
                                        .accessibilityLabel(String(localized: "选择歌词"))
                                        .accessibilityValue(line.text)
                                        .accessibilityHint(String(localized: "选择后可跳转到这一句"))
                                    }
                                    .padding(.leading, 8)
                                    .background(selectedLine?.id == line.id ? Sunset.accent(scheme).opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 8))
                                    .id(line.id)
                                    .accessibilityAddTraits(active == line.id ? .isSelected : [])
                                }
                            }
                        }
                        .padding(.horizontal, 12).padding(.vertical, 12)
                        .frame(maxWidth: 720, alignment: .leading)
                        .frame(maxWidth: .infinity)
                    }
                    .modifier(LyricsManualScrollModifier {
                        if !lyrics.lines.isEmpty { followsPlayback = false }
                    })
                    .onChange(of: active) { _, id in
                        if followsPlayback, let id { scroll(to: id, proxy: proxy) }
                    }
                    .onChange(of: contentKey, initial: true) { _, key in
                        lyrics = Lyrics(key.text)
                        followsPlayback = true
                        selectedLine = nil
                    }
                    .task(id: contentKey) {
                        // Wait until the newly parsed rows are in the scroll view.
                        await Task.yield()
                        guard !Task.isCancelled else { return }
                        if let id = lyrics.activeLine(at: store.position) { proxy.scrollTo(id, anchor: .center) }
                        else if let first = lyrics.lines.first { proxy.scrollTo(first.id, anchor: .top) }
                    }

                    if !lyrics.lines.isEmpty {
                        HStack {
                            if let line = selectedLine {
                                Button {
                                    store.seek(to: line.time)
                                    selectedLine = nil
                                    followsPlayback = true
                                    scroll(to: line.id, proxy: proxy)
                                } label: {
                                    Label(String(localized: "从这里播放 \(playbackTime(line.time))"), systemImage: "play.fill")
                                }
                                .disabled(store.isManaging)
                            }
                            Spacer(minLength: 8)
                            if !followsPlayback {
                                Button(String(localized: "回到当前句")) {
                                    selectedLine = nil
                                    followsPlayback = true
                                    if let active { scroll(to: active, proxy: proxy) }
                                    else if let first = lyrics.lines.first { proxy.scrollTo(first.id, anchor: .top) }
                                }
                            }
                        }
                        .font(.caption).buttonStyle(.plain)
                        .foregroundStyle(Sunset.accent(scheme))
                        .frame(minHeight: 44).padding(.horizontal, 12)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Sunset.panel(scheme))
        // A regular tap yields to child buttons and the scroll view's drag gesture.
        // Do not use a simultaneous/high-priority gesture: controls must not dismiss lyrics.
        .contentShape(Rectangle())
        .onTapGesture(perform: returnToCover)
        .accessibilityAction(named: String(localized: "返回封面"), returnToCover)
        .fileImporter(isPresented: $choosingLyrics, allowedContentTypes: [.plainText, .data]) { result in
            // The destination is captured before presenting the file picker.
            guard let id = importTrackID else { return }
            importTrackID = nil
            switch result {
            case .success(let url): Task {
                do {
                    try await store.importLyrics(from: url, trackID: id)
                } catch { problem = error.localizedDescription }
            }
            case .failure(let error): problem = error.localizedDescription
            }
        }
        .alert(String(localized: "无法导入歌词"), isPresented: Binding(get: { problem != nil }, set: { if !$0 { problem = nil } })) {
            Button(String(localized: "好")) { problem = nil }
        } message: { Text(problem ?? "") }
    }

    private var header: some View {
        HStack(spacing: 0) {
            Text(String(localized: "歌词"))
                .font(.subheadline.weight(.medium)).accessibilityAddTraits(.isHeader)
                .padding(.leading, 12)
            Spacer(minLength: 4)
            Menu {
                Button(String(localized: "导入歌词…"), action: beginImport)
                    .disabled(store.current == nil || store.isBusy)
            } label: {
                Image(systemName: "ellipsis").frame(width: 44, height: 44)
            }
            .accessibilityLabel(String(localized: "歌词设置"))
            Button(action: returnToCover) {
                Image(systemName: "photo").frame(width: 44, height: 44)
            }
            .accessibilityLabel(String(localized: "返回封面"))
            .help(String(localized: "返回封面"))
        }
        .buttonStyle(.plain)
        .foregroundStyle(Sunset.secondary(scheme))
    }

    private func beginImport() {
        guard let id = store.current?.id, !store.isBusy else { return }
        importTrackID = id
        choosingLyrics = true
    }

    private func scroll(to id: Int, proxy: ScrollViewProxy) {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) {
            proxy.scrollTo(id, anchor: .center)
        }
    }
}

private struct LyricsManualScrollModifier: ViewModifier {
    let onManualScroll: () -> Void
    @ViewBuilder func body(content: Content) -> some View {
        if #available(iOS 18.0, macOS 15.0, *) {
            content.onScrollPhaseChange { _, phase in
                if phase == .interacting || phase == .decelerating { onManualScroll() }
            }
        } else {
            content.simultaneousGesture(DragGesture(minimumDistance: 10).onChanged { value in
                if abs(value.translation.height) > abs(value.translation.width) { onManualScroll() }
            })
        }
    }
}
