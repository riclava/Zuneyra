import XCTest
#if os(macOS)
import Carbon
#endif

@MainActor final class LibraryUXUITests: XCTestCase {
    #if os(macOS)
    private var previousInput: TISInputSource?
    #endif

    override func setUpWithError() throws { continueAfterFailure = false }

    private func application() -> XCUIApplication {
        #if os(macOS)
        previousInput = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
        let filter = [kTISPropertyInputSourceID as String: "com.apple.keylayout.ABC"] as CFDictionary
        let layouts = TISCreateInputSourceList(filter, false).takeRetainedValue() as! [TISInputSource]
        if let abc = layouts.first { XCTAssertEqual(TISSelectInputSource(abc), noErr) }
        #endif
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-playback", "--ui-test-library-ux", "--ui-test-session", UUID().uuidString]
        app.launch()
        XCTAssertTrue(app.buttons["专辑 UI Fixture"].waitForExistence(timeout: 15))
        return app
    }

    private func finish(_ app: XCUIApplication) {
        app.terminate()
        #if os(macOS)
        if let previousInput { TISSelectInputSource(previousInput) }
        #endif
    }

    private func choose(_ title: String, in app: XCUIApplication) {
        #if os(macOS)
        app.menuItems[title].firstMatch.tap()
        #else
        app.buttons[title].firstMatch.tap()
        #endif
    }

    func testVisibleSongMenuAddsNextWithoutStartingPlayback() {
        let app = application()
        defer { finish(app) }
        app.buttons["歌曲"].firstMatch.tap()
        let actions = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", "歌曲操作 Search Regression")).firstMatch
        XCTAssertTrue(actions.waitForExistence(timeout: 5))
        XCTAssertTrue(actions.isHittable)
        actions.tap()
        choose("下一首播放", in: app)

        XCTAssertFalse(app.buttons["暂停"].exists)
        app.buttons["queueToolbar"].firstMatch.tap()
        let queued = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "queueEntry-"))
        XCTAssertTrue(queued.firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(queued.count, 1)
        XCTAssertTrue(queued.firstMatch.label.contains("Search Regression"))
        XCTAssertFalse(app.buttons["暂停 Search Regression"].exists)
    }

    func testNoResultsCanBeClearedWithoutLosingAlbumContext() {
        let app = application()
        defer { finish(app) }
        app.buttons["专辑 UI Fixture"].tap()
        let search = app.textFields["librarySearchField"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        XCTAssertEqual(search.placeholderValue, "搜索此专辑")
        search.tap()
        search.typeText("zzzzmissingtrack")
        #if os(macOS)
        search.typeKey(.tab, modifierFlags: [])
        #else
        search.typeText("\n")
        #endif

        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "play-track-"))
        let empty = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in rows.count == 0 }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [empty], timeout: 5), .completed)
        XCTAssertTrue(app.staticTexts["UI Fixture"].firstMatch.exists)
        let clear = app.buttons["清除搜索"].firstMatch
        XCTAssertTrue(clear.isHittable)
        clear.tap()

        XCTAssertTrue(app.buttons["播放 Search Regression"].waitForExistence(timeout: 5))
        XCTAssertEqual(search.placeholderValue, "搜索此专辑")
        XCTAssertTrue(app.buttons["所有专辑"].exists)
        XCTAssertEqual(rows.count, 3)
    }

    func testAlbumPlaybackQueueFollowsVisibleTrackNumbers() {
        let app = application()
        defer { finish(app) }
        app.buttons["专辑 UI Fixture"].tap()
        let expected = ["Search Regression", "Queue Third", "Queue Second"]
        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "play-track-"))
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(rows.count, expected.count)
        for (index, title) in expected.enumerated() {
            XCTAssertEqual(rows.element(boundBy: index).label, "播放 \(title)")
        }

        app.buttons["播放全部"].firstMatch.tap()
        let pause = app.buttons["暂停"].firstMatch
        XCTAssertTrue(pause.waitForExistence(timeout: 10))
        pause.tap()
        XCTAssertTrue(app.buttons["打开正在播放：Search Regression"].exists)
        app.buttons["queueToolbar"].firstMatch.tap()

        let queued = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "queueEntry-"))
        XCTAssertTrue(queued.firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(queued.count, expected.count)
        for (index, title) in expected.enumerated() {
            XCTAssertTrue(queued.element(boundBy: index).label.contains(title))
        }
    }

    #if os(iOS)
    func testPlayerControlsFitAndSeekCommitsOnRelease() {
        let app = application()
        defer { finish(app) }
        app.buttons["专辑 UI Fixture"].tap()
        app.buttons["播放全部"].firstMatch.tap()
        let pause = app.buttons["暂停"].firstMatch
        XCTAssertTrue(pause.waitForExistence(timeout: 10))
        pause.tap()
        let openPlayer = app.buttons["打开正在播放：Search Regression"]
        openPlayer.tap()
        let transport = app.buttons["playerTransportToggle"]
        XCTAssertTrue(transport.waitForExistence(timeout: 5))
        XCTAssertTrue(transport.isHittable, "The primary playback control should fit without scrolling.")
        XCTAssertLessThanOrEqual(transport.frame.maxY, app.windows.firstMatch.frame.maxY)

        app.sliders["播放进度"].adjust(toNormalizedSliderPosition: 0.5)
        app.buttons["完成"].firstMatch.tap()
        openPlayer.tap()
        let elapsed = app.staticTexts["playbackElapsed"]
        XCTAssertTrue(elapsed.waitForExistence(timeout: 5))
        let committed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let seconds = elapsed.label.split(separator: ":").last.flatMap { Int($0) } ?? -1
            return (12...18).contains(seconds)
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [committed], timeout: 5), .completed)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Player controls and committed seek"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
    #endif
}
