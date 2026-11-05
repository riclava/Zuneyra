import Foundation
import Testing
@testable import Zuneyra

struct AdaptiveLayoutTests {
    @Test @MainActor func librarySwipesFollowCategoryOrderAndRespectBoundaries() {
        typealias Section = ContentView.LibrarySection
        let sections = Section.allCases
        for (index, section) in sections.enumerated() {
            let left = section.destinationForSwipe(horizontal: -100, vertical: 8, startX: 180, width: 390)
            let right = section.destinationForSwipe(horizontal: 100, vertical: 8, startX: 180, width: 390)
            #expect(left == (index + 1 < sections.count ? sections[index + 1] : nil))
            #expect(right == (index > 0 ? sections[index - 1] : nil))
        }
        #expect(Section.songs.destinationForSwipe(horizontal: -100, vertical: 70, startX: 180, width: 390) == nil)
        #expect(Section.songs.destinationForSwipe(horizontal: -40, vertical: 0, startX: 180, width: 390) == nil)
        #expect(Section.songs.destinationForSwipe(horizontal: 100, vertical: 0, startX: 12, width: 390) == nil)
        #expect(Section.songs.destinationForSwipe(horizontal: -100, vertical: 0, startX: 380, width: 390) == nil)
    }

    @Test @MainActor func libraryDragTracksFingerAndResistsAtEnds() {
        typealias Section = ContentView.LibrarySection
        #expect(Section.songs.offsetForSwipe(horizontal: -30, vertical: 2, startX: 180, width: 390) == -30)
        #expect(Section.songs.offsetForSwipe(horizontal: 120, vertical: 2, startX: 180, width: 390) == 120)
        #expect(Section.songs.offsetForSwipe(horizontal: -30, vertical: 60, startX: 180, width: 390) == 0)
        #expect(Section.songs.offsetForSwipe(horizontal: 80, vertical: 0, startX: 12, width: 390) == 0)
        #expect(Section.albums.offsetForSwipe(horizontal: 100, vertical: 0, startX: 180, width: 390) == 15)
        #expect(Section.playlists.offsetForSwipe(horizontal: -100, vertical: 0, startX: 180, width: 390) == -15)
    }

    @Test @MainActor func libraryGestureLocksItsInitialAxis() {
        typealias Axis = ContentView.LibraryDragAxis
        #expect(Axis.resolve(locked: nil, horizontal: 30, vertical: 4, canPage: true) == .horizontal)
        #expect(Axis.resolve(locked: .horizontal, horizontal: 30, vertical: 100, canPage: true) == .horizontal)
        #expect(Axis.resolve(locked: nil, horizontal: 4, vertical: 30, canPage: true) == .vertical)
        #expect(Axis.resolve(locked: .vertical, horizontal: 100, vertical: 30, canPage: true) == .vertical)
        #expect(Axis.resolve(locked: nil, horizontal: 40, vertical: 0, canPage: false) == .vertical)
    }

    @Test @MainActor func libraryFlickUsesMomentumWithoutTurningSmallTouchesIntoPageChanges() {
        typealias Section = ContentView.LibrarySection
        #expect(Section.songs.destinationForRelease(horizontal: -30, projected: -140, startX: 180, width: 390) == .artists)
        #expect(Section.songs.destinationForRelease(horizontal: 30, projected: 140, startX: 180, width: 390) == .albums)
        #expect(Section.songs.destinationForRelease(horizontal: -12, projected: -200, startX: 180, width: 390) == nil)
        #expect(Section.songs.destinationForRelease(horizontal: -30, projected: 140, startX: 180, width: 390) == nil)
        #expect(Section.songs.destinationForRelease(horizontal: -30, projected: -140, startX: 380, width: 390) == nil)
        #expect(Section.playlists.destinationForRelease(horizontal: -30, projected: -140, startX: 180, width: 390) == nil)
    }

    @Test func resizingSupportsCompactExpandedAndShortWindows() {
        // Representative window sizes, not unverified Duo hardware dimensions.
        let sizes: [CGSize] = [.init(width: 390, height: 760), .init(width: 720, height: 700),
                               .init(width: 1000, height: 700), .init(width: 1000, height: 320)]
        let layouts = sizes.map { AdaptiveLayout(size: $0, accessibility: false) }
        #expect(layouts.map(\.showsSidebar) == [false, false, true, false])
        #expect(layouts.map(\.horizontalPlayer) == [false, true, true, true])
        #expect(layouts.map(\.playerCompanion) == [false, false, true, false])
        #expect(layouts.map(\.expandedMiniPlayer) == [false, true, true, true])
        for size in sizes {
            let accessible = AdaptiveLayout(size: size, accessibility: true)
            #expect(!accessible.showsSidebar && !accessible.horizontalPlayer && !accessible.playerCompanion && !accessible.expandedMiniPlayer)
        }
    }
}
