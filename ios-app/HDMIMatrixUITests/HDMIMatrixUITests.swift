import XCTest

/// End-to-end UI tests against the demo matrix (`-ui-testing` forces demo
/// mode with throwaway settings, so runs are repeatable).
///
/// `testWalkthrough` doubles as the source of the user guide's screenshots:
/// each `snap("NN-name")` is saved in the test results, and
/// `scripts/capture_screenshots.sh` copies them into docs/ios-guide/images/.
final class HDMIMatrixUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()
        XCTAssertTrue(app.buttons["route-1-3"].waitForExistence(timeout: 15), "demo matrix never loaded")
    }

    // MARK: - Walkthrough (also produces the guide's screenshots)

    func testWalkthrough() throws {
        // Routing
        snap("01-routing")

        let macBookToLeft = app.buttons["route-1-2"]
        macBookToLeft.tap()
        expectSelected(macBookToLeft)
        snap("02-route-input")

        let rightPower = app.switches["output-2-power"]
        toggle(rightPower)
        expectValue(rightPower, "0")
        let preselectedWhileOff = app.buttons["route-2-1"]
        XCTAssertTrue(preselectedWhileOff.isEnabled, "sources should remain selectable while the output is off")
        preselectedWhileOff.tap()
        expectSelected(preselectedWhileOff)
        snap("03-output-power-off")
        toggle(rightPower)
        expectValue(rightPower, "1")

        // Audio
        let arc = app.segmentedControls["audio-arc"]
        scrollTo(arc)
        arc.buttons["Out-B"].tap()
        expectSelected(arc.buttons["Out-B"])
        snap("04-audio")
        app.swipeDown()

        // Rename an output
        app.buttons["output-1-name"].tap()
        let field = app.textFields["rename-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        replaceText(in: field, with: "Projector")
        snap("05-rename")
        app.buttons["Save"].tap()
        expectLabel(app.buttons["output-1-name"], contains: "Projector")

        // Inputs & EDID
        app.tabBars.buttons["Inputs"].tap()
        let edid = app.buttons["input-2-edid"]
        XCTAssertTrue(edid.waitForExistence(timeout: 5))
        snap("06-inputs")
        edid.tap()
        let preset = app.buttons["11  4K HDR 10Bit 2CH"]
        XCTAssertTrue(preset.waitForExistence(timeout: 5))
        snap("07-edid-menu")
        preset.tap()
        expectLabel(edid, contains: "4K HDR 10Bit 2CH")

        // Device
        app.tabBars.buttons["Device"].tap()
        let connection = app.buttons["connection-row"]
        XCTAssertTrue(connection.waitForExistence(timeout: 5))
        snap("08-device")
        connection.tap()
        XCTAssertTrue(app.switches["demo-toggle"].waitForExistence(timeout: 5))
        snap("09-connection-settings")
        app.buttons["Cancel"].tap()

        let reboot = app.buttons["Reboot matrix"]
        scrollTo(reboot)
        snap("10-danger-zone")
        reboot.tap()
        let confirm = app.buttons["Reboot"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        snap("11-reboot-confirm")
        confirm.tap()

        // A successful reboot is a heads-up, not an error.
        XCTAssertTrue(app.alerts["Heads up"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.alerts["Couldn't do that"].exists)
        app.alerts["Heads up"].buttons["OK"].tap()
    }

    // MARK: - Focused checks

    func testRenameRejectsInvalidNames() {
        app.buttons["output-2-name"].tap()
        let field = app.textFields["rename-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))

        replaceText(in: field, with: "TV")
        XCTAssertFalse(app.buttons["Save"].isEnabled, "names under 3 characters are rejected")

        replaceText(in: field, with: "Living Room")
        XCTAssertFalse(app.buttons["Save"].isEnabled, "spaces are rejected")

        replaceText(in: field, with: "Living_Room")
        XCTAssertTrue(app.buttons["Save"].isEnabled)
        app.buttons["Cancel"].tap()
        expectLabel(app.buttons["output-2-name"], contains: "Right")
    }

    func testRoutingSurvivesPolling() {
        let chip = app.buttons["route-2-4"]
        chip.tap()
        expectSelected(chip)
        // Outlive a couple of 3s polls: the route must stick, not flicker back.
        sleep(7)
        XCTAssertTrue(chip.isSelected)
        XCTAssertFalse(app.buttons["route-2-3"].isSelected)
    }

    func testConnectionAccessoryShowsDemo() {
        XCTAssertTrue(app.staticTexts["Connected"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Demo matrix"].exists)
    }

    // MARK: - Helpers

    private func snap(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func toggle(_ element: XCUIElement) {
        XCTAssertTrue(element.waitForExistence(timeout: 5))
        // Tap the switch's thumb end; a centered tap can land on the label area.
        element.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5)).tap()
    }

    private func replaceText(in field: XCUIElement, with text: String) {
        field.tap()
        let current = (field.value as? String) ?? ""
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count + 2))
        field.typeText(text)
    }

    private func scrollTo(_ element: XCUIElement, maxSwipes: Int = 6) {
        var swipes = 0
        while !element.isHittable && swipes < maxSwipes {
            app.swipeUp()
            swipes += 1
        }
        XCTAssertTrue(element.isHittable, "couldn't scroll to \(element)")
    }

    private func expectSelected(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        let predicate = NSPredicate(format: "isSelected == true")
        let result = XCTWaiter.wait(for: [expectation(for: predicate, evaluatedWith: element)], timeout: 5)
        XCTAssertEqual(result, .completed, "\(element) never became selected", file: file, line: line)
    }

    private func expectValue(_ element: XCUIElement, _ value: String, file: StaticString = #filePath, line: UInt = #line) {
        let predicate = NSPredicate(format: "value == %@", value)
        let result = XCTWaiter.wait(for: [expectation(for: predicate, evaluatedWith: element)], timeout: 5)
        XCTAssertEqual(result, .completed, "\(element) value never became \(value)", file: file, line: line)
    }

    private func expectLabel(_ element: XCUIElement, contains text: String, file: StaticString = #filePath, line: UInt = #line) {
        let predicate = NSPredicate(format: "label CONTAINS %@", text)
        let result = XCTWaiter.wait(for: [expectation(for: predicate, evaluatedWith: element)], timeout: 5)
        XCTAssertEqual(result, .completed, "\(element) label never contained \(text)", file: file, line: line)
    }
}
