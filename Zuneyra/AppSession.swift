import Foundation

/// The phone and CarPlay join one startup task and one player, including cold launch.
@MainActor final class AppSession {
    static let shared: AppSession = {
        #if DEBUG
        if UITestFixture.enabled {
            return AppSession(store: UITestFixture.makeStore(), prepare: { try await UITestFixture.seed($0.repository) })
        }
        #endif
        return AppSession(store: PlayerStore())
    }()
    let store: PlayerStore
    private let prepare: (@MainActor (PlayerStore) async throws -> Void)?
    private var startup: Task<Void, Never>?
    init(store: PlayerStore, prepare: (@MainActor (PlayerStore) async throws -> Void)? = nil) {
        self.store = store; self.prepare = prepare
    }
    func start() async {
        if let startup { await startup.value; return }
        let task = Task {
            do { try await prepare?(store) }
            catch { store.errorMessage = error.localizedDescription }
            await store.load()
        }
        startup = task
        await task.value
    }
}
