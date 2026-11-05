import Foundation

struct ImportFailure: Codable, Identifiable, Sendable {
    var id = UUID()
    let source: URL
    let reason: String
    let bookmark: Data?
    var filename: String { source.lastPathComponent }

    init(source: URL, reason: String) {
        self.source = source
        self.reason = reason
        #if os(macOS)
        bookmark = try? source.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess], includingResourceValuesForKeys: nil, relativeTo: nil)
        #else
        bookmark = try? source.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
        #endif
    }
    func resolvedURL() -> URL {
        guard let bookmark else { return source }
        var stale = false
        #if os(macOS)
        let options: URL.BookmarkResolutionOptions = [.withSecurityScope, .withoutUI]
        #else
        let options: URL.BookmarkResolutionOptions = [.withoutUI]
        #endif
        return (try? URL(resolvingBookmarkData: bookmark, options: options, relativeTo: nil, bookmarkDataIsStale: &stale)) ?? source
    }
}

struct ImportRecord: Codable, Identifiable, Sendable {
    let id: UUID
    let date: Date
    let source: String
    let report: ImportReport
}

struct StorageUsage: Sendable {
    var audio: Int64 = 0
    var incoming: Int64 = 0
    var artwork: Int64 = 0
    var database: Int64 = 0
    var temporary: Int64 = 0
    var incomingFiles = 0
    var total: Int64 { audio + incoming + artwork + database + temporary }
    static func formatted(_ bytes: Int64) -> String { ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) }
}

struct CleanupResult: Sendable {
    var removed = 0
    var bytes: Int64 = 0
    var skipped = 0
    var failures: [String] = []
    var message: String {
        var text = String(localized: "已清理 \(removed) 个文件，移除的文件合计 \(StorageUsage.formatted(bytes))。")
        if skipped > 0 { text += String(localized: "保留 \(skipped) 个尚未入库、已更改或无法核对的文件。") }
        if !failures.isEmpty { text += "\n" + failures.joined(separator: "\n") }
        return text
    }
}

struct DeletionManifest: Codable {
    struct Entry: Codable { let trackID: UUID; let files: [String] }
    let entries: [Entry]
}

// Older records may contain only text failures, without retryable file references.
extension ImportRecord {
    var failureCount: Int { max(report.failures.count, report.failureItems.count) }
}

enum ImportHistoryFilter: String, CaseIterable, Identifiable {
    case all, failures, stopped
    var id: String { rawValue }
    var title: String { switch self {
    case .all: String(localized: "全部")
    case .failures: String(localized: "有失败")
    case .stopped: String(localized: "已停止")
    } }
    func includes(_ record: ImportRecord) -> Bool { switch self {
    case .all: true
    case .failures: record.failureCount > 0
    case .stopped: record.report.cancelled
    } }
}
