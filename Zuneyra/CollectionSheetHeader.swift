import SwiftUI

/// Navigation belongs to the paper surface instead of a separate system toolbar.
struct CollectionSheetHeader: View {
    @Environment(\.colorScheme) private var scheme
    let title: String
    var subtitle: String? = nil
    var back: (() -> Void)? = nil
    var close: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 12) {
            if let back {
                Button(action: back) {
                    Image(systemName: "chevron.left").frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("返回")
                .help("返回")
                .keyboardShortcut(.cancelAction)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(.headline, design: .serif, weight: .medium))
                    .accessibilityAddTraits(.isHeader)
                if let subtitle {
                    Text(subtitle).font(.caption).foregroundStyle(Sunset.secondary(scheme))
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            if let close {
                Button(action: close) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .medium))
                        .frame(width: 30, height: 30)
                        .background(Sunset.secondary(scheme).opacity(0.09), in: Circle())
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("关闭")
                .help("关闭")
                .keyboardShortcut(.cancelAction)
            }
        }
        .foregroundStyle(Sunset.secondary(scheme))
        .padding(.horizontal, 28).padding(.vertical, 12)
    }
}

extension View {
    func collectionSheetChrome() -> some View {
        #if os(macOS)
        toolbar(.hidden, for: .windowToolbar)
        #else
        toolbar(.hidden, for: .navigationBar, .bottomBar)
            .navigationBarBackButtonHidden(true)
        #endif
    }
}
