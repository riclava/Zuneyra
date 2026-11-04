import SwiftUI

@main
struct ZuneyraApp: App {
    @State private var store = AppSession.shared.store
    var body: some Scene {
        WindowGroup {
            ContentView().environment(store).task { await AppSession.shared.start() }
        }
    }
}
