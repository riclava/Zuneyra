import SwiftUI

@main
struct ZuneyraApp: App {
    @State private var store: PlayerStore
    init() {
        #if DEBUG
        if UITestFixture.enabled { store = UITestFixture.makeStore(); return }
        #endif
        store = PlayerStore()
    }
    var body: some Scene {
        WindowGroup {
            ContentView().environment(store).task {
                if store.isLoading {
                    #if DEBUG
                    if UITestFixture.enabled {
                        do { try await UITestFixture.seed(store.repository) }
                        catch { store.errorMessage = error.localizedDescription }
                    }
                    #endif
                    await store.load()
                }
            }
        }
    }
}
