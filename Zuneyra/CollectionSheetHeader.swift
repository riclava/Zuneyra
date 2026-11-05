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

extension View {
    /// Cancel row actions once a drag starts, and keep them suppressed through scroll deceleration.
    func guardActionsWhileScrolling() -> some View {
        modifier(ScrollActionGuard())
    }
}

private struct ScrollActionGuard: ViewModifier {
    @GestureState private var dragActive = false
    @State private var dragging = false
    @State private var scrolling = false
    @State private var suppressActions = false
    @State private var releaseTask: Task<Void, Never>?

    func body(content: Content) -> some View {
        observeScrolling(content)
            // Publish a custom flag; never disable the ScrollView itself.
            .transformEnvironment(\.libraryActionsSuppressed) { $0 = $0 || suppressActions }
            .simultaneousGesture(
                DragGesture(minimumDistance: 8)
                    .updating($dragActive) { _, active, _ in active = true }
                    .onChanged { _ in
                        guard !dragging else { return }
                        dragging = true
                        suppress()
                    }
                    .onEnded { _ in
                        dragging = false
                        releaseWhenIdle()
                    }
            )
            .onChange(of: dragActive) { _, active in
                if !active {
                    dragging = false
                    releaseWhenIdle()
                }
            }
            .onDisappear {
                releaseTask?.cancel()
                releaseTask = nil
                dragging = false
                scrolling = false
                suppressActions = false
            }
    }

    @ViewBuilder private func observeScrolling(_ content: Content) -> some View {
        if #available(iOS 18.0, macOS 15.0, *) {
            content.onScrollPhaseChange { _, phase in
                switch phase {
                case .interacting, .decelerating:
                    scrolling = true
                    suppress()
                case .idle:
                    scrolling = false
                    releaseWhenIdle()
                default: break
                }
            }
        } else {
            content
        }
    }

    private func suppress() {
        releaseTask?.cancel()
        releaseTask = nil
        suppressActions = true
    }

    private func releaseWhenIdle() {
        guard suppressActions, !dragging, !scrolling else { return }
        releaseTask?.cancel()
        releaseTask = Task { @MainActor in
            // Do not re-enable a pressed row during the same touch-up event.
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled, !dragging, !scrolling else { return }
            suppressActions = false
            releaseTask = nil
        }
    }
}

private struct LibraryActionsSuppressedKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var libraryActionsSuppressed: Bool {
        get { self[LibraryActionsSuppressedKey.self] }
        set { self[LibraryActionsSuppressedKey.self] = newValue }
    }
}

extension View {
    /// Apply only to a Button, Menu, or NavigationLink, never a scrolling container.
    func protectLibraryAction() -> some View { modifier(LibraryActionProtection()) }
}

private struct LibraryActionProtection: ViewModifier {
    @Environment(\.libraryActionsSuppressed) private var suppressed
    func body(content: Content) -> some View {
        content
            // Preserve the control's normal colors; suppression is only a touch-routing rule.
            .allowsHitTesting(!suppressed)
            .overlay {
                if suppressed {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { }
                        .accessibilityHidden(true)
                }
            }
    }
}
