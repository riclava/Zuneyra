import SwiftUI

@main
struct ZuneyraApp: App {
    @State private var store = PlayerStore()
    var body: some Scene {
        WindowGroup {
            ContentView().environment(store).task { if store.isLoading { await store.load() } }
        }
    }
}
