//
//  ZuneyraUITests.swift
//  ZuneyraUITests
//
//  Created by RicLava on 4/11/26.
//

import XCTest

final class ZuneyraUITests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    @MainActor
    func testExample() throws {
        // UI tests must launch the application that they test.
        let app = XCUIApplication()
        app.launch()

        // Use XCTAssert and related functions to verify your tests produce the correct results.
        // XCUIAutomation Documentation
        // https://developer.apple.com/documentation/xcuiautomation
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
    @MainActor
    func testSearchRemainsVisibleDuringPlaybackAndFiltering() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-playback"]
        app.launch()
        let search = app.textFields["librarySearchField"]
        XCTAssertTrue(search.waitForExistence(timeout: 15))
        app.buttons["歌曲"].firstMatch.tap()
        let play = app.buttons["播放全部"]
        XCTAssertTrue(play.waitForExistence(timeout: 10))
        play.tap()
        XCTAssertTrue(app.buttons["暂停"].firstMatch.waitForExistence(timeout: 10))
        XCTAssertTrue(search.isHittable)
        #if os(macOS)
        search.click()
        #else
        search.tap()
        #endif
        search.typeText("Regression")
        XCTAssertEqual(search.value as? String, "Regression")
        XCTAssertTrue(app.buttons["播放 Search Regression"].waitForExistence(timeout: 5))
        XCTAssertTrue(search.isHittable)
        app.buttons["暂停"].firstMatch.tap()
    }

    @MainActor
    func testMultiSelectDeleteAndManagementEntry() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-playback"]
        app.launch()
        let select = app.buttons["selectTracks"].firstMatch
        XCTAssertTrue(select.waitForExistence(timeout: 15))
        select.tap()
        let track = app.buttons["选择 Search Regression"]
        XCTAssertTrue(track.waitForExistence(timeout: 10))
        track.tap()
        app.buttons["deleteSelectedTracks"].firstMatch.tap()
        let confirm = app.buttons["删除音频副本"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 10))
        confirm.tap()
        let result = app.buttons["好"].firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 10))
        result.tap()
        XCTAssertFalse(app.buttons["播放 Search Regression"].exists)
        app.buttons["libraryManagement"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["当前设备保存的文件大小"].waitForExistence(timeout: 10))
        app.buttons["完成"].firstMatch.tap()
    }

    @MainActor
    func testQueueModesReorderRemoveAndClearKeepLibrary() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-playback", "--ui-test-queue"]
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.buttons["歌曲"].firstMatch.waitForExistence(timeout: 15))
        app.buttons["歌曲"].firstMatch.tap()
        let play = app.buttons["播放 Search Regression"]
        XCTAssertTrue(play.waitForExistence(timeout: 10))
        play.tap()
        XCTAssertTrue(app.buttons["暂停"].firstMatch.waitForExistence(timeout: 10))
        app.buttons["暂停"].firstMatch.tap()
        app.buttons["queueToolbar"].firstMatch.tap()
        let shuffle = app.buttons["shuffleMode"].firstMatch
        XCTAssertTrue(shuffle.waitForExistence(timeout: 5))
        shuffle.tap()
        XCTAssertTrue(shuffle.label.contains("随机播放"))
        shuffle.tap()
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Playback queue"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        let repeatMode = app.buttons["repeatMode"].firstMatch
        repeatMode.tap()
        XCTAssertTrue(repeatMode.label.contains("列表循环"))
        repeatMode.tap()
        XCTAssertTrue(repeatMode.label.contains("单曲循环"))
        repeatMode.tap()
        let thirdActions = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "队列操作 Queue Third")).firstMatch
        XCTAssertTrue(thirdActions.waitForExistence(timeout: 5))
        thirdActions.tap()
        #if os(macOS)
        app.menuItems["上移"].firstMatch.tap()
        #else
        app.buttons["上移"].firstMatch.tap()
        #endif
        let entries = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "queueEntry-"))
        XCTAssertTrue(entries.element(boundBy: 1).label.contains("Queue Third"))
        thirdActions.tap()
        #if os(macOS)
        app.menuItems["移出队列"].firstMatch.tap()
        #else
        app.buttons["移出队列"].firstMatch.tap()
        #endif
        XCTAssertFalse(thirdActions.exists)
        app.descendants(matching: .any)["queueActions"].firstMatch.tap()
        #if os(macOS)
        app.menuItems["清空待播"].firstMatch.tap()
        #else
        app.buttons["清空待播"].firstMatch.tap()
        #endif
        XCTAssertTrue(app.staticTexts["emptyUpcoming"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["继续播放 Search Regression"].firstMatch.exists)
        app.buttons["完成"].firstMatch.tap()
        XCTAssertTrue(app.buttons["播放 Queue Third"].exists)
        XCTAssertTrue(app.buttons["播放 Queue Second"].exists)
    }

    @MainActor
    func testSongMenuBuildsQueueWithoutStartingPlayback() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-playback"]
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.buttons["歌曲"].firstMatch.waitForExistence(timeout: 15))
        app.buttons["歌曲"].firstMatch.tap()
        let track = app.buttons["播放 Search Regression"]
        XCTAssertTrue(track.waitForExistence(timeout: 10))
        #if os(macOS)
        track.rightClick()
        app.menuItems["下一首播放"].firstMatch.tap()
        track.rightClick()
        app.menuItems["稍后播放"].firstMatch.tap()
        #else
        track.press(forDuration: 1)
        app.buttons["下一首播放"].firstMatch.tap()
        track.press(forDuration: 1)
        app.buttons["稍后播放"].firstMatch.tap()
        #endif
        XCTAssertFalse(app.buttons["暂停"].exists)
        app.buttons["queueToolbar"].firstMatch.tap()
        let entries = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "queueEntry-"))
        XCTAssertEqual(entries.count, 2)
        entries.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons["暂停 Search Regression"].waitForExistence(timeout: 10))
        let actions = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "队列操作 Search Regression"))
        actions.element(boundBy: 0).tap()
        #if os(macOS)
        app.menuItems["移出队列"].firstMatch.tap()
        #else
        app.buttons["移出队列"].firstMatch.tap()
        #endif
        XCTAssertEqual(entries.count, 1)
        XCTAssertFalse(app.buttons["暂停 Search Regression"].exists)
        app.buttons["完成"].firstMatch.tap()
        XCTAssertTrue(track.exists)
    }

}
