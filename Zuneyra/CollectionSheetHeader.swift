import SwiftUI
#if os(iOS)
import UIKit
#endif

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

#if os(iOS)
struct SwipeSafeButton<Label: View>: View {
    let action: () -> Void
    @ViewBuilder var label: () -> Label
    @Environment(\.libraryActionsSuppressed) private var suppressed

    var body: some View {
        Button {
            if !TouchMovementRecognizer.cancelled && !suppressed { action() }
        } label: { label() }
        .background(TouchMovementObserver().allowsHitTesting(false))
        .accessibilityAction { action() }
    }
}

/// Observe touches simultaneously without preventing or delaying other gestures.
/// Cancellation survives page removal and resets on the next physical touch.
private final class TouchMovementRecognizer: UIGestureRecognizer, UIGestureRecognizerDelegate {
    override init(target: Any?, action: Selector?) {
        super.init(target: target, action: action)
        delegate = self
    }
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool { true }
    static var cancelled = false
    private var origins: [UITouch: CGPoint] = [:]

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        if origins.isEmpty { Self.cancelled = false }
        for touch in touches { origins[touch] = touch.location(in: view) }
        state = state == .possible ? .began : .changed
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        for touch in touches {
            guard let origin = origins[touch] else { continue }
            let point = touch.location(in: view)
            if hypot(point.x - origin.x, point.y - origin.y) >= 8 {
                Self.cancelled = true
                state = .changed
                return
            }
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        touchesMoved(touches, with: event)
        for touch in touches { origins.removeValue(forKey: touch) }
        if origins.isEmpty { state = .ended }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        Self.cancelled = true
        origins.removeAll()
        state = .cancelled
    }

    override func reset() { super.reset(); origins.removeAll() }
    override func canPrevent(_ preventedGestureRecognizer: UIGestureRecognizer) -> Bool { false }
    override func canBePrevented(by preventingGestureRecognizer: UIGestureRecognizer) -> Bool { false }
}

private struct TouchMovementObserver: UIViewRepresentable {
    final class ObserverView: UIView {
        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard let window, !(window.gestureRecognizers ?? []).contains(where: { $0 is TouchMovementRecognizer }) else { return }
            let observer = TouchMovementRecognizer(target: nil, action: nil)
            observer.cancelsTouchesInView = false
            observer.delaysTouchesBegan = false
            observer.delaysTouchesEnded = false
            window.addGestureRecognizer(observer)
        }
    }
    func makeUIView(context: Context) -> ObserverView { ObserverView() }
    func updateUIView(_ uiView: ObserverView, context: Context) { }
}
#else
typealias SwipeSafeButton<Label: View> = Button<Label>
#endif

/// Keep the native disclosure's state, but route expansion through the same
/// touch cancellation as library rows instead of its built-in tap recognizer.
struct SwipeSafeDisclosureStyle: DisclosureGroupStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SwipeSafeButton { configuration.isExpanded.toggle() } label: {
                HStack {
                    configuration.label
                    Spacer(minLength: 8)
                    Image(systemName: configuration.isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption.weight(.semibold))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(configuration.isExpanded ? String(localized: "已展开") : String(localized: "已收起"))
            .protectLibraryAction()
            if configuration.isExpanded { configuration.content }
        }
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
            // Let touch-up finish without imposing a delay on the next tap.
            await Task.yield()
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
            // Do not change isEnabled: that dims labels during a drag.
            // SwipeSafeButton cancels an in-flight action in its action closure.
            .allowsHitTesting(!suppressed)
            .overlay {
                if suppressed {
                    Color.clear.contentShape(Rectangle()).onTapGesture { }
                        .accessibilityHidden(true)
                }
            }
    }
}
