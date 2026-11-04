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

}
