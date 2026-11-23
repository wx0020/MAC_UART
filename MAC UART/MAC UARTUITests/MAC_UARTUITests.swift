//
//  MAC_UARTUITests.swift
//  MAC UARTUITests
//
//  Created by 翔吴 on 2026/11/19.
//

import XCTest

final class MAC_UARTUITests: XCTestCase {

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
    func testLoadAndValidateOfflineCommand() throws {
        let app = XCUIApplication()
        let fixture = #"[{"id":"203F2CB9-606B-496B-95A2-396DD0ECDA55","name":"UX fixture","input":"01 FF","format":"HEX","ending":""}]"#
        let data = fixture.utf8.map { String(format: "%02x", $0) }.joined()
        app.launchArguments = ["-interface.language", "english", "-serial.commands", "<" + data + ">"]
        app.launch()

        app.buttons["Serial settings"].click()
        let settings = app.windows["Serial settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 4))
        settings.buttons[XCUIIdentifierCloseWindow].click()

        let actions = app.scrollViews.menuButtons.firstMatch
        actions.click()
        app.menuItems["Load into send area"].click()
        let draft = app.textViews["sendDraft"]
        XCTAssertEqual(draft.value as? String, "01 FF")
        XCTAssertTrue(app.buttons["Save as command"].isEnabled)
        app.typeKey("a", modifierFlags: .command)
        app.typeText("01 F")
        XCTAssertTrue(app.staticTexts["Use two hex digits per byte, e.g. 01 A0 FF."].exists)
        XCTAssertFalse(app.buttons["Save as command"].isEnabled)
        app.typeText("0")
        XCTAssertTrue(app.buttons["Save as command"].isEnabled)
        actions.click()
        app.menuItems["Load into send area"].click()
        XCTAssertEqual(draft.value as? String, "01 FF")
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
