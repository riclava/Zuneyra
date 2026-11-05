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
                .accessibilityLabel(String(localized: "返回"))
                .help(String(localized: "返回"))
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
                .accessibilityLabel(String(localized: "关闭"))
                .help(String(localized: "关闭"))
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

/// Keep browser-style forward history when a navigation stack pops a destination.
struct PageNavigation<Route: Equatable> {
    private(set) var path: [Route] = []
    private(set) var future: [Route] = []
    var canGoBack: Bool { !path.isEmpty }
    var canGoForward: Bool { !future.isEmpty }

    mutating func setPath(_ next: [Route]) {
        guard next != path else { return }
        if next.count < path.count, Array(path.prefix(next.count)) == next {
            future.append(contentsOf: path.dropFirst(next.count).reversed())
        } else {
            future.removeAll()
        }
        path = next
    }
    mutating func back() {
        guard let last = path.popLast() else { return }
        future.append(last)
    }
    mutating func forward() {
        guard let next = future.popLast() else { return }
        path.append(next)
    }
}

extension View {
    func edgeNavigation(back: (() -> Void)? = nil, forward: (() -> Void)? = nil) -> some View {
        modifier(EdgeNavigationModifier(back: back, forward: forward))
    }
}

private struct EdgeNavigationModifier: ViewModifier {
    let back: (() -> Void)?
    let forward: (() -> Void)?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @ViewBuilder func body(content: Content) -> some View {
        #if os(iOS)
        GeometryReader { geometry in
            content
                .frame(width: geometry.size.width, height: geometry.size.height)
                .simultaneousGesture(DragGesture(minimumDistance: 24).onEnded { value in
                    let dx = value.translation.width
                    let dy = value.translation.height
                    guard abs(dx) >= 64, abs(dx) > abs(dy) * 2 else { return }
                    let action: (() -> Void)?
                    if value.startLocation.x <= 24, dx > 0 { action = back }
                    else if value.startLocation.x >= geometry.size.width - 24, dx < 0 { action = forward }
                    else { action = nil }
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.22)) { action?() }
                })
        }
        #else
        content
        #endif
    }
}
