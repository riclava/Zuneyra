import SwiftUI

/// Uses the space offered by the containing window or sheet, never a device model.
struct AdaptiveLayout {
    let size: CGSize
    let accessibility: Bool

    var showsSidebar: Bool { size.width >= 820 && size.height >= 560 && !accessibility }
    var horizontalPlayer: Bool { size.width >= 560 && size.height >= 260 && !accessibility }
    var playerCompanion: Bool { size.width >= 820 && size.height >= 560 && !accessibility }
    var expandedMiniPlayer: Bool { size.width >= 700 && !accessibility }
}
