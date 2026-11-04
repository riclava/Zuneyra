import XCTest
#if os(macOS)
import Carbon
#endif

@MainActor final class PlaylistUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    #if os(macOS)
    private var previousInput: TISInputSource?
    #endif
    private func finish(_ app: XCUIApplication) {
        app.terminate()
        #if os(macOS)
        if let previousInput { TISSelectInputSource(previousInput) }
        #endif
    }
    private func application() -> XCUIApplication {
        #if os(macOS)
        previousInput = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
        let filter = [kTISPropertyInputSourceID as String: "com.apple.keylayout.ABC"] as CFDictionary
        let layouts = TISCreateInputSourceList(filter, false).takeRetainedValue() as! [TISInputSource]
        if let abc = layouts.first { XCTAssertEqual(TISSelectInputSource(abc), noErr) }
        else { TISSelectInputSource(TISCopyCurrentASCIICapableKeyboardInputSource().takeRetainedValue()) }
        #endif
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-playback", "--ui-test-queue", "--ui-test-session", UUID().uuidString]
        app.launch()
        XCTAssertTrue(app.buttons["歌单"].firstMatch.waitForExistence(timeout: 15))
        return app
    }
    private func expectCount(_ query: XCUIElementQuery, _ count: Int, file: StaticString = #filePath, line: UInt = #line) {
        let settled = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in query.count == count }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [settled], timeout: 5), .completed, file: file, line: line)
    }
    private func item(_ app: XCUIApplication, _ title: String) {
        #if os(macOS)
        app.menuItems[title].firstMatch.tap()
        #else
        app.buttons[title].firstMatch.tap()
        #endif
    }
    private func context(_ element: XCUIElement) {
        #if os(macOS)
        element.rightClick()
        #else
        element.press(forDuration: 1)
        #endif
    }
    private func actions(_ app: XCUIApplication) { app.descendants(matching: .any)["playlistActions"].firstMatch.tap() }

    func testCreateEditRestorePlayAndDeletePlaylist() throws {
        let app = application()
        defer { finish(app) }
        app.buttons["歌单"].firstMatch.tap()
        app.buttons["createPlaylist"].firstMatch.tap()
        let name = app.textFields["playlistNameField"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap(); name.typeText("Roadtrip ")
        #if os(macOS)
        name.typeKey(.tab, modifierFlags: []) // Commit composition without submitting the form twice.
        #endif
        app.buttons["savePlaylistName"].firstMatch.tap()
        let card = app.buttons["歌单 Roadtrip"].firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        card.tap()
        app.buttons["addPlaylistSongs"].firstMatch.tap()
        for title in ["Search Regression", "Queue Second", "Queue Third"] {
            let button = app.buttons["添加歌曲 \(title)"]
            XCTAssertTrue(button.waitForExistence(timeout: 5)); button.tap()
        }
        app.buttons["confirmAddPlaylistSongs"].firstMatch.tap()
        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "playlistTrack-"))
        expectCount(rows, 3)
        app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "歌单歌曲操作 Queue Third")).firstMatch.tap()
        item(app, "上移")
        let reordered = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", "Queue Third"), object: rows.element(boundBy: 1))
        XCTAssertEqual(XCTWaiter.wait(for: [reordered], timeout: 5), .completed)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Playlist detail"; screenshot.lifetime = .keepAlways; add(screenshot)
        app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "歌单歌曲操作 Search Regression")).firstMatch.tap()
        item(app, "从歌单移除")
        expectCount(rows, 2)
        actions(app); item(app, "重命名")
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        #if os(macOS)
        name.typeKey("a", modifierFlags: .command)
        #else
        name.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        name.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 20))
        #endif
        name.typeText("Nightdrive ")
        #if os(macOS)
        name.typeKey(.tab, modifierFlags: []) // Commit composition without submitting the form twice.
        #endif
        app.buttons["savePlaylistName"].firstMatch.tap()
        XCTAssertTrue(app.buttons["playPlaylist"].firstMatch.waitForExistence(timeout: 5))
        app.terminate(); app.launch()
        app.buttons["歌单"].firstMatch.tap()
        let renamed = app.buttons["歌单 Nightdrive"].firstMatch
        XCTAssertTrue(renamed.waitForExistence(timeout: 10)); renamed.tap()
        expectCount(rows, 2)
        XCTAssertTrue(rows.element(boundBy: 0).label.contains("Queue Third"))
        app.buttons["playPlaylist"].firstMatch.tap()
        XCTAssertTrue(app.buttons["暂停"].firstMatch.waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["打开正在播放：Queue Third"].exists)
        app.buttons["暂停"].firstMatch.tap()
        app.buttons["shufflePlaylist"].firstMatch.tap()
        XCTAssertTrue(app.buttons["暂停"].firstMatch.waitForExistence(timeout: 10))
        app.buttons["暂停"].firstMatch.tap()
        actions(app); item(app, "删除歌单")
        let confirm = app.buttons["删除歌单"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5)); confirm.tap()
        XCTAssertTrue(app.buttons["createPlaylist"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(renamed.exists)
        app.terminate(); app.launch()
        app.buttons["歌曲"].firstMatch.tap()
        for title in ["Search Regression", "Queue Second", "Queue Third"] { XCTAssertTrue(app.buttons["播放 \(title)"].exists) }
    }

    func testSongBatchAndAlbumAddToPlaylistDeduplicates() throws {
        let app = application()
        defer { finish(app) }
        app.buttons["歌曲"].firstMatch.tap()
        context(app.buttons["播放 Search Regression"])
        item(app, "添加到歌单")
        let name = app.textFields["newPlaylistFromTracksName"]
        XCTAssertTrue(name.waitForExistence(timeout: 5)); name.tap(); name.typeText("Favourites ")
        #if os(macOS)
        name.typeKey(.tab, modifierFlags: [])
        #endif
        app.buttons["createPlaylistWithTracks"].firstMatch.tap()
        XCTAssertTrue(app.buttons["selectTracks"].firstMatch.waitForExistence(timeout: 5))
        app.buttons["selectTracks"].firstMatch.tap()
        app.buttons["选择 Queue Second"].tap(); app.buttons["选择 Queue Third"].tap()
        app.descendants(matching: .any)["selectedTracksActions"].firstMatch.tap()
        item(app, "添加到歌单")
        let existing = app.buttons["加入歌单 Favourites"].firstMatch
        XCTAssertTrue(existing.waitForExistence(timeout: 5)); existing.tap()
        let dismissed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: existing)
        XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: 5), .completed)
        app.buttons["歌单"].firstMatch.tap()
        let card = app.buttons["歌单 Favourites"].firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 5)); card.tap()
        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "playlistTrack-"))
        expectCount(rows, 3)
        app.terminate(); app.launch()
        let album = app.buttons["专辑 UI Fixture"].firstMatch
        XCTAssertTrue(album.waitForExistence(timeout: 10)); context(album)
        item(app, "添加到歌单")
        XCTAssertTrue(existing.waitForExistence(timeout: 5)); existing.tap()
        app.buttons["歌单"].firstMatch.tap(); card.tap()
        expectCount(rows, 3)
    }

    #if os(iOS)
    func testPlaybackContinuesInBackground() throws {
        let app = application()
        defer { finish(app) }
        app.buttons["歌曲"].firstMatch.tap()
        app.buttons["播放全部"].tap()
        XCTAssertTrue(app.buttons["暂停"].firstMatch.waitForExistence(timeout: 10))
        app.buttons["打开正在播放：Search Regression"].tap()
        let elapsed = app.staticTexts["playbackElapsed"]
        XCTAssertTrue(elapsed.waitForExistence(timeout: 5))
        func seconds(_ text: String) -> Int { let parts = text.split(separator: ":").compactMap { Int($0) }; return parts.count == 2 ? parts[0] * 60 + parts[1] : 0 }
        let before = seconds(elapsed.label)
        XCUIDevice.shared.press(.home)
        let interval = expectation(description: "Allow audio to progress in background")
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { interval.fulfill() }
        wait(for: [interval], timeout: 5)
        app.activate()
        XCTAssertTrue(elapsed.waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(seconds(elapsed.label), before + 2)
        XCTAssertTrue(app.buttons["暂停"].firstMatch.exists)
        app.buttons["暂停"].firstMatch.tap()
    }
    #endif
}
