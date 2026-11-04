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

    var body: some View {
        VStack(spacing: 0) {
            CollectionSheetHeader(title: "音乐库管理", close: { dismiss() })
            VStack(spacing: 0) {
                HStack(spacing: 24) {
                    managementTab("存储空间", value: 0)
                    managementTab("导入记录", value: 1)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 24)
                .background(Sunset.background(scheme))
                .overlay(alignment: .bottom) { Rectangle().fill(Sunset.stroke(scheme)).frame(height: 1) }
                if store.isManaging { ProgressView("正在核对并处理文件…").padding() }
                if store.isImporting { HStack { ProgressView().controlSize(.small); Text(store.importProgress); Button("取消") { store.cancelImport() } }.padding(.horizontal, 24).padding(.vertical, 12) }
                if tab == 1 && store.history.isEmpty {
                    StudioEmptyState(symbol: "clock.arrow.circlepath", title: "还没有导入记录", detail: "之后的导入结果会保存在这里。")
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
        .confirmationDialog("清理已入库的传入文件？", isPresented: $confirmIncoming, titleVisibility: .visible) {
            Button("核对并清理", role: .destructive) { Task { await store.cleanIncomingFiles() } }
        } message: { Text("逐一核对文件内容与音乐库副本，仅删除仍有完整相同副本的传入文件。未入库、已更改、损坏或无法核对的文件将保留。") }
        .confirmationDialog("清理封面缓存？", isPresented: $confirmArtwork, titleVisibility: .visible) {
            Button("清理封面缓存", role: .destructive) { Task { await store.clearArtwork() } }
        } message: { Text("音乐和收藏不受影响。再次浏览时会从音频中重新生成封面。") }
        .alert("操作结果", isPresented: Binding(get: { store.managementMessage != nil }, set: { if !$0 { store.managementMessage = nil } })) {
            Button("好") { store.managementMessage = nil }
        } message: { Text(store.managementMessage ?? "") }
        .alert("无法完成操作", isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) {
            Button("好") { store.errorMessage = nil }
        } message: { Text(store.errorMessage ?? "") }
        .fileImporter(isPresented: $choosingFiles, allowedContentTypes: [.audio, .folder], allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls): store.importFiles(urls)
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
        if let usage = store.storage {
            VStack(alignment: .leading, spacing: 10) {
                Text("已使用空间").font(.caption.weight(.semibold)).foregroundStyle(Sunset.secondary(scheme))
                Text(StorageUsage.formatted(usage.total)).font(.system(.largeTitle, design: .serif).weight(.medium).monospacedDigit())
                Text("当前设备保存的文件大小").font(.footnote).foregroundStyle(Sunset.secondary(scheme))
            }
            storageDistribution(usage)
            VStack(spacing: 0) {
                storageRow("音乐副本", bytes: usage.audio, icon: "music.note")
                if store.supportsIncomingFiles { storageRow("电脑传入文件", bytes: usage.incoming, icon: "cable.connector") }
                storageRow("封面缓存", bytes: usage.artwork, icon: "photo")
                storageRow("音乐库与导入记录", bytes: usage.database, icon: "internaldrive")
                if usage.temporary > 0 { storageRow("任务临时文件", bytes: usage.temporary, icon: "clock") }
            }.padding(.horizontal, 20)
                .background(Sunset.elevated(scheme), in: RoundedRectangle(cornerRadius: 5))
                .overlay { RoundedRectangle(cornerRadius: 5).stroke(Sunset.stroke(scheme), lineWidth: 1) }
            if store.supportsIncomingFiles {
                VStack(alignment: .leading, spacing: 10) {
                    Button("清理已入库的传入文件", systemImage: "trash") { confirmIncoming = true }
                        .buttonStyle(StudioButtonStyle())
                        .disabled(store.isBusy || usage.incomingFiles == 0)
                    Text("Finder 传入文件和音乐库副本各占一份空间。清理前会核对两份内容；清理后仍可播放音乐库中的副本。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { maintenanceActions(usage) }
                VStack(alignment: .leading, spacing: 8) { maintenanceActions(usage) }
            }
        } else { ProgressView("正在统计存储空间…") }
    }

    private func maintenanceActions(_ usage: StorageUsage) -> some View {
        Group {
            Button("清理封面缓存", systemImage: "photo") { confirmArtwork = true }
                .disabled(store.isBusy || usage.artwork == 0)
            Button("刷新存储占用", systemImage: "arrow.clockwise") { Task { await store.refreshManagement() } }
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
                Label { Text("音乐副本") } icon: { Rectangle().fill(Sunset.accent(scheme)).frame(width: 6, height: 6) }
                Label { Text("其他文件") } icon: { Rectangle().fill(Sunset.secondary(scheme).opacity(0.55)).frame(width: 6, height: 6) }
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
        Text("保留最近 100 次导入结果").font(.footnote).foregroundStyle(.secondary)
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
                        Button("重试失败文件", systemImage: "arrow.clockwise") { store.retryImport(record) }.disabled(store.isBusy)
                        Button("重新选择来源…", systemImage: "folder") { choosingFiles = true }.disabled(store.isBusy)
                        Text("若文件已移动或访问权限失效，请重新选择来源。重试会生成一条新记录。")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }.padding(.vertical, 12)
            } label: {
                VStack(alignment: .leading, spacing: 5) {
                    Text(record.source + (record.report.cancelled ? " · 已停止" : "")).font(.headline)
                    Text(record.date.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                    Text("导入 \(record.report.added) · 重复 \(record.report.duplicates) · 失败 \(record.report.failures.count)").font(.subheadline)
                }.padding(.vertical, 6)
            }
            Divider()
        }
    }
}
