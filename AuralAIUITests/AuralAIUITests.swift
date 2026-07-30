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

        XCTAssertTrue(speechTab.waitForExistence(timeout: 3))
        XCTAssertTrue(grammarTab.exists)

        grammarTab.click()
        XCTAssertTrue(app.secureTextFields.firstMatch.waitForExistence(timeout: 2))

        let grammarScreenshot = XCTAttachment(screenshot: app.screenshot())
        grammarScreenshot.name = "Grammar Settings"
        grammarScreenshot.lifetime = .keepAlways
        add(grammarScreenshot)

        speechTab.click()
        XCTAssertTrue(app.sliders.firstMatch.waitForExistence(timeout: 2))
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
            addScreenshot(of: popup, named: "Grammar Results - \(appearance)")
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
