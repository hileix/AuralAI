//
//  AuralAIUITests.swift
//  AuralAIUITests
//
//  Created by mac on 2026/3/21.
//

import XCTest

final class AuralAIUITests: XCTestCase {

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
    func testSettingsTabs() throws {
        let app = XCUIApplication()
        app.launch()

        let speechTab = app.buttons["settings.tab.speech"]
        let grammarTab = app.buttons["settings.tab.grammar"]
        let historyTab = app.buttons["settings.tab.history"]

        XCTAssertTrue(speechTab.waitForExistence(timeout: 3))
        XCTAssertTrue(app.windows["AuralAI Dev Settings"].exists)
        XCTAssertTrue(app.staticTexts["AuralAI Dev"].exists)
        XCTAssertTrue(grammarTab.exists)
        XCTAssertTrue(historyTab.exists)

        grammarTab.click()
        XCTAssertTrue(app.secureTextFields.firstMatch.waitForExistence(timeout: 2))

        let grammarScreenshot = XCTAttachment(screenshot: app.screenshot())
        grammarScreenshot.name = "Grammar Settings"
        grammarScreenshot.lifetime = .keepAlways
        add(grammarScreenshot)

        speechTab.click()
        XCTAssertTrue(app.sliders.firstMatch.waitForExistence(timeout: 2))

        historyTab.click()
        XCTAssertTrue(app.descendants(matching: .any)["settings.history"].waitForExistence(timeout: 2))
    }

    @MainActor
    func testGrammarLoadingPresentation() throws {
        for appearance in ["Light", "Dark"] {
            let app = XCUIApplication()
            app.launchEnvironment["AURALAI_UI_TEST_GRAMMAR_STATE"] = "loading"
            app.launchEnvironment["AURALAI_UI_TEST_APPEARANCE"] = appearance.lowercased()
            app.launchArguments += ["-AppleInterfaceStyle", appearance]
            app.launch()

            let loadingStatus = app.descendants(matching: .any)["grammar.status.loading"]
            XCTAssertTrue(loadingStatus.waitForExistence(timeout: 3))
            XCTAssertLessThanOrEqual(loadingStatus.frame.width, 40)
            addScreenshot(of: loadingStatus, named: "Grammar Loading - \(appearance)")
            app.terminate()
        }
    }

    @MainActor
    func testGrammarResultsPresentation() throws {
        for appearance in ["Light", "Dark"] {
            let app = XCUIApplication()
            app.launchEnvironment["AURALAI_UI_TEST_GRAMMAR_STATE"] = "results"
            app.launchEnvironment["AURALAI_UI_TEST_APPEARANCE"] = appearance.lowercased()
            app.launchArguments += ["-AppleInterfaceStyle", appearance]
            app.launch()

            let popup = app.dialogs.firstMatch
            XCTAssertTrue(popup.waitForExistence(timeout: 3))
            XCTAssertEqual(app.buttons.matching(identifier: "grammar.results.option.1").count, 1)
            let pinButton = app.buttons["grammar.results.pin"]
            XCTAssertTrue(pinButton.exists)
            pinButton.click()
            XCTAssertTrue(pinButton.label == "Unpin" || pinButton.label == "取消固定")
            popup.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.05)).click()
            addScreenshot(of: popup, named: "Grammar Results - \(appearance)")
            app.terminate()
        }
    }

    @MainActor
    func testGrammarStreamingResultsPresentation() throws {
        let app = XCUIApplication()
        app.launchEnvironment["AURALAI_UI_TEST_GRAMMAR_STATE"] = "streaming"
        app.launch()

        let streamingStatus = app.descendants(matching: .any)["grammar.results.streaming"]
        XCTAssertTrue(streamingStatus.waitForExistence(timeout: 3))

        let option = app.buttons["grammar.results.option.1"]
        XCTAssertTrue(option.exists)
        XCTAssertFalse(option.isEnabled)
        addScreenshot(of: app.dialogs.firstMatch, named: "Grammar Results - Streaming")
    }

    @MainActor
    func testGrammarHistoryPresentation() throws {
        for appearance in ["Light", "Dark"] {
            let app = XCUIApplication()
            app.launchEnvironment["AURALAI_UI_TEST_HISTORY_PREVIEW"] = "1"
            app.launchEnvironment["AURALAI_UI_TEST_APPEARANCE"] = appearance.lowercased()
            app.launchArguments += ["-AppleInterfaceStyle", appearance]
            app.launch()

            let historyTab = app.buttons["settings.tab.history"]
            XCTAssertTrue(historyTab.waitForExistence(timeout: 3))
            historyTab.click()

            let history = app.descendants(matching: .any)["settings.history"]
            XCTAssertTrue(history.waitForExistence(timeout: 2))
            XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "settings.history.empty").count, 0)
            let settingsWindow = app.windows.firstMatch
            XCTAssertTrue(settingsWindow.exists)
            let screenshot = XCTAttachment(screenshot: settingsWindow.screenshot())
            screenshot.name = "Grammar History - \(appearance)"
            screenshot.lifetime = .keepAlways
            add(screenshot)
            app.terminate()
        }
    }

    @MainActor
    private func addScreenshot(of element: XCUIElement, named name: String) {
        let screenshot = XCTAttachment(screenshot: element.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
