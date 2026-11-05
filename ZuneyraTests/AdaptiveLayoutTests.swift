import Foundation
import Testing
@testable import Zuneyra

struct AdaptiveLayoutTests {
    @Test func resizingSupportsCompactExpandedAndShortWindows() {
        // Representative window sizes, not unverified Duo hardware dimensions.
        let sizes: [CGSize] = [.init(width: 390, height: 760), .init(width: 720, height: 700),
                               .init(width: 1000, height: 700), .init(width: 1000, height: 320)]
        let layouts = sizes.map { AdaptiveLayout(size: $0, accessibility: false) }
        #expect(layouts.map(\.showsSidebar) == [false, false, true, false])
        #expect(layouts.map(\.horizontalPlayer) == [false, true, true, false])
        #expect(layouts.map(\.playerCompanion) == [false, false, true, false])
        #expect(layouts.map(\.expandedMiniPlayer) == [false, true, true, true])
        for size in sizes {
            let accessible = AdaptiveLayout(size: size, accessibility: true)
            #expect(!accessible.showsSidebar && !accessible.horizontalPlayer && !accessible.playerCompanion && !accessible.expandedMiniPlayer)
        }
    }
}
