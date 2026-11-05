import SwiftUI
import UniformTypeIdentifiers

struct LibraryManagementView: View {
    @Environment(PlayerStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @State private var tab: Int
    init(initialTab: Int = 0) { _tab = State(initialValue: initialTab) }
    @State private var confirmIncoming = false
    @State private var confirmArtwork = false
    @State private var choosingFiles = false
    @State private var choosingBackupFolder = false
    @State private var restoringBackup = false
    @State private var choosingReference = false
    @State private var choosingPlaylistFolder = false
    @State private var importingPlaylists = false

    var body: some View {
        VStack(spacing: 0) {
            CollectionSheetHeader(title: String(localized: "音乐库管理"), close: { dismiss() })
            VStack(spacing: 0) {
                HStack(spacing: 24) {
                    managementTab(String(localized: "存储空间"), value: 0)
                    managementTab(String(localized: "导入记录"), value: 1)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 24)
                .background(Sunset.background(scheme))
                .overlay(alignment: .bottom) { Rectangle().fill(Sunset.stroke(scheme)).frame(height: 1) }
                if store.isManaging { ProgressView(String(localized: "正在核对并处理文件…")).padding() }
                if store.isRescanningMetadata {
                    HStack {
                        ProgressView().controlSize(.small)
                        Text(store.metadataProgress)
                        Button(String(localized: "取消")) { store.cancelMetadataRescan() }
                    }.padding(.horizontal, 24).padding(.vertical, 12)
                }
                if store.isImporting { HStack { ProgressView().controlSize(.small); Text(store.importProgress); Button(String(localized: "取消")) { store.cancelImport() } }.padding(.horizontal, 24).padding(.vertical, 12) }
                if tab == 1 && store.history.isEmpty {
                    StudioEmptyState(symbol: "clock.arrow.circlepath", title: String(localized: "还没有导入记录"), detail: String(localized: "之后的导入结果会保存在这里。"))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 24) {
                            if tab == 0 { storageContent }
                            else { historyContent }
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(24)
                    }
                }
            }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Sunset.background(scheme).ignoresSafeArea())
        .tint(Sunset.accent(scheme))
        .collectionSheetChrome()
        .task { await store.refreshManagement() }
        .onChange(of: store.isImporting) { _, active in if !active { Task { await store.refreshManagement() } } }
        .confirmationDialog(String(localized: "清理已入库的传入文件？"), isPresented: $confirmIncoming, titleVisibility: .visible) {
            Button(String(localized: "核对并清理"), role: .destructive) { Task { await store.cleanIncomingFiles() } }
        } message: { Text(String(localized: "逐一核对文件内容与音乐库副本，仅删除仍有完整相同副本的传入文件。未入库、已更改、损坏或无法核对的文件将保留。")) }
        .confirmationDialog(String(localized: "清理封面缓存？"), isPresented: $confirmArtwork, titleVisibility: .visible) {
            Button(String(localized: "清理封面缓存"), role: .destructive) { Task { await store.clearArtwork() } }
        } message: { Text(String(localized: "音乐和收藏不受影响。再次浏览时会从音频中重新生成封面。")) }
        .alert(String(localized: "操作结果"), isPresented: Binding(get: { store.managementMessage != nil }, set: { if !$0 { store.managementMessage = nil } })) {
            Button(String(localized: "好")) { store.managementMessage = nil }
        } message: { Text(store.managementMessage ?? "") }
        .alert(String(localized: "无法完成操作"), isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) {
            Button(String(localized: "好")) { store.errorMessage = nil }
        } message: { Text(store.errorMessage ?? "") }
        .fileImporter(isPresented: $choosingFiles, allowedContentTypes: [.audio, .folder], allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls): store.importFiles(urls)
            case .failure(let error): store.errorMessage = error.localizedDescription
            }
        }
        .fileImporter(isPresented: $choosingPlaylistFolder, allowedContentTypes: [.folder]) { result in
            switch result {
            case .success(let url): Task { await store.transferPlaylists(at: url, importing: importingPlaylists) }
            case .failure(let error): store.errorMessage = error.localizedDescription
            }
        }
        .fileImporter(isPresented: $choosingReference, allowedContentTypes: [.folder], allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls): store.importFiles(urls, referencing: true)
            case .failure(let error): store.errorMessage = error.localizedDescription
            }
        }
        .fileImporter(isPresented: $choosingBackupFolder, allowedContentTypes: [.folder]) { result in
            switch result {
            case .success(let url): Task { await store.transferBackup(at: url, restoring: restoringBackup) }
            case .failure(let error): store.errorMessage = error.localizedDescription
            }
        }
        #if os(macOS)
        .frame(width: 640, height: 680)
        #endif
    }

    private func managementTab(_ title: String, value: Int) -> some View {
        Button { tab = value } label: {
            Text(title)
                .font(.subheadline.weight(tab == value ? .semibold : .medium))
                .foregroundStyle(tab == value ? Sunset.accent(scheme) : Sunset.secondary(scheme))
                .frame(minHeight: 48)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(tab == value ? Sunset.accent(scheme) : .clear).frame(height: 2).padding(.bottom, 1)
                }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(tab == value ? .isSelected : [])
    }

    @ViewBuilder private var storageContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(String(localized: "重新扫描音乐元数据"), systemImage: "arrow.triangle.2.circlepath") { store.rescanMetadata() }
                .buttonStyle(StudioButtonStyle()).disabled(store.isBusy || store.tracks.isEmpty)
            Text(String(localized: "重新读取标签、碟号、封面和增益信息，并补充缺失歌词。保留收藏、歌单、队列及已有歌词，不修改音频文件。"))
                .font(.footnote).foregroundStyle(.secondary)
        }

        VStack(alignment: .leading, spacing: 12) {
            #if os(macOS)
            Button(String(localized: "引用音乐文件夹／重新授权…"), systemImage: "folder") { choosingReference = true }.disabled(store.isBusy)
            Text(String(localized: "直接播放原位置文件，不额外保存音频副本。重新选择文件夹可扫描新增歌曲和更新已有引用的授权；外置磁盘需保持连接。")).font(.footnote).foregroundStyle(.secondary)
            #endif
            Text(String(localized: "备份与迁移")).font(.headline)
            Button(String(localized: "导出 M3U8 歌单与音频…")) { importingPlaylists = false; choosingPlaylistFolder = true }.disabled(store.isBusy || store.playlists.isEmpty)
            Button(String(localized: "导入 M3U8 所在文件夹…")) { importingPlaylists = true; choosingPlaylistFolder = true }.disabled(store.isBusy)
            Button(String(localized: "导出音乐库备份…"), systemImage: "square.and.arrow.up") {
                restoringBackup = false; choosingBackupFolder = true
            }.disabled(store.isBusy)
            Button(String(localized: "从备份合并恢复…"), systemImage: "square.and.arrow.down") {
                restoringBackup = true; choosingBackupFolder = true
            }.disabled(store.isBusy)
            Text(String(localized: "备份包含音乐、收藏和歌单。恢复前会校验全部音频；相同音乐不重复复制，歌单作为新歌单加入。请选择备份文件夹。")).font(.footnote).foregroundStyle(.secondary)
        }

        if let usage = store.storage {
            VStack(alignment: .leading, spacing: 10) {
                Text(String(localized: "已使用空间")).font(.caption.weight(.semibold)).foregroundStyle(Sunset.secondary(scheme))
                Text(StorageUsage.formatted(usage.total)).font(.system(.largeTitle, design: .serif).weight(.medium).monospacedDigit())
                Text(String(localized: "当前设备保存的文件大小")).font(.footnote).foregroundStyle(Sunset.secondary(scheme))
            }
            storageDistribution(usage)
            VStack(spacing: 0) {
                storageRow(String(localized: "音乐副本"), bytes: usage.audio, icon: "music.note")
                if store.supportsIncomingFiles { storageRow(String(localized: "电脑传入文件"), bytes: usage.incoming, icon: "cable.connector") }
                storageRow(String(localized: "封面缓存"), bytes: usage.artwork, icon: "photo")
                storageRow(String(localized: "音乐库与导入记录"), bytes: usage.database, icon: "internaldrive")
                if usage.temporary > 0 { storageRow(String(localized: "任务临时文件"), bytes: usage.temporary, icon: "clock") }
            }.padding(.horizontal, 20)
                .background(Sunset.elevated(scheme), in: RoundedRectangle(cornerRadius: 5))
                .overlay { RoundedRectangle(cornerRadius: 5).stroke(Sunset.stroke(scheme), lineWidth: 1) }
            if store.supportsIncomingFiles {
                VStack(alignment: .leading, spacing: 10) {
                    Button(String(localized: "清理已入库的传入文件"), systemImage: "trash") { confirmIncoming = true }
                        .buttonStyle(StudioButtonStyle())
                        .disabled(store.isBusy || usage.incomingFiles == 0)
                    Text(String(localized: "Finder 传入文件和音乐库副本各占一份空间。清理前会核对两份内容；清理后仍可播放音乐库中的副本。"))
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { maintenanceActions(usage) }
                VStack(alignment: .leading, spacing: 8) { maintenanceActions(usage) }
            }
        } else { ProgressView(String(localized: "正在统计存储空间…")) }
    }

    private func maintenanceActions(_ usage: StorageUsage) -> some View {
        Group {
            Button(String(localized: "清理封面缓存"), systemImage: "photo") { confirmArtwork = true }
                .disabled(store.isBusy || usage.artwork == 0)
            Button(String(localized: "刷新存储占用"), systemImage: "arrow.clockwise") { Task { await store.refreshManagement() } }
                .disabled(store.isBusy)
        }.buttonStyle(StudioButtonStyle())
    }

    private func storageDistribution(_ usage: StorageUsage) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { geometry in
                let total = Double(max(1, usage.total))
                HStack(spacing: 0) {
                    Rectangle().fill(Sunset.accent(scheme)).frame(width: geometry.size.width * Double(usage.audio) / total)
                    Rectangle().fill(Sunset.secondary(scheme).opacity(0.55))
                }
            }
            .frame(height: 6)
            .clipShape(RoundedRectangle(cornerRadius: 2))
            .accessibilityHidden(true)
            HStack(spacing: 16) {
                Label { Text(String(localized: "音乐副本")) } icon: { Rectangle().fill(Sunset.accent(scheme)).frame(width: 6, height: 6) }
                Label { Text(String(localized: "其他文件")) } icon: { Rectangle().fill(Sunset.secondary(scheme).opacity(0.55)).frame(width: 6, height: 6) }
            }.font(.caption).foregroundStyle(Sunset.secondary(scheme))
        }
    }

    private func storageRow(_ title: String, bytes: Int64, icon: String) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: icon).frame(width: 20).foregroundStyle(Sunset.secondary(scheme)).accessibilityHidden(true)
                Text(title).font(.subheadline)
                Spacer(minLength: 8)
                Text(StorageUsage.formatted(bytes)).font(.subheadline.monospacedDigit()).foregroundStyle(Sunset.secondary(scheme))
            }.padding(.vertical, 14)
            Rectangle().fill(Sunset.stroke(scheme)).frame(height: 1)
        }
    }
    @ViewBuilder private var historyContent: some View {
        Text(String(localized: "保留最近 100 次导入结果")).font(.footnote).foregroundStyle(.secondary)
        ForEach(store.history) { record in
            DisclosureGroup {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(record.report.failureItems) { item in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.filename).font(.subheadline.bold())
                            Text(item.reason).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                        }
                    }
                    if !record.report.failureItems.isEmpty {
                        Button(String(localized: "重试失败文件"), systemImage: "arrow.clockwise") { store.retryImport(record) }.disabled(store.isBusy)
                        Button(String(localized: "重新选择来源…"), systemImage: "folder") { choosingFiles = true }.disabled(store.isBusy)
                        Text(String(localized: "若文件已移动或访问权限失效，请重新选择来源。重试会生成一条新记录。"))
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }.padding(.vertical, 12)
            } label: {
                VStack(alignment: .leading, spacing: 5) {
                    Text(record.source + (record.report.cancelled ? String(localized: " · 已停止") : "")).font(.headline)
                    Text(record.date.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                    Text(String(localized: "导入 \(record.report.added) · 重复 \(record.report.duplicates) · 失败 \(record.report.failures.count)")).font(.subheadline)
                }.padding(.vertical, 6)
            }
            Divider()
        }
    }
}
