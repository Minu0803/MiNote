import XCTest

@MainActor final class MiNoteUITests: XCTestCase {
    func testInkUndoRedoAndRelaunch() throws {
        let app = XCUIApplication()
        app.launch()
        let count = app.staticTexts["strokeCount"]
        XCTAssertTrue(count.waitForExistence(timeout: 15))
        let initialCount = Int(count.label.split(separator: " ").last ?? "") ?? 0
        let canvas = app.scrollViews["noteCanvas"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        let start = canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.3))
        let end = canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4))
        start.press(forDuration: 0.1, thenDragTo: end)
        let expected = "획 \(initialCount + 1)"
        XCTAssertTrue(waitForLabel(count, expected))
        app.buttons["undo"].tap()
        XCTAssertTrue(waitForLabel(count, "획 \(initialCount)"))
        app.buttons["redo"].tap()
        XCTAssertTrue(waitForLabel(count, expected))
        let saveStatus = app.staticTexts["saveStatus"]
        let didSave = waitForLabel(saveStatus, "저장 완료")
        XCTAssertTrue(didSave, "저장 상태: \(saveStatus.label)")
        app.terminate()
        app.launch()
        XCTAssertTrue(waitForLabel(app.staticTexts["strokeCount"], expected))
    }

    func testPDFImportNavigationAndRelaunch() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.buttons["importPDF"].waitForExistence(timeout: 10))
        app.buttons["importPDF"].tap()
        print("PICKER-HIERARCHY", app.debugDescription)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.lifetime = .keepAlways
        add(attachment)
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        search.tap()
        search.typeText("MiNote-Sample")
        let sample = app.staticTexts["MiNote-Sample"].firstMatch
        XCTAssertTrue(sample.waitForExistence(timeout: 15))
        sample.tap()
        XCTAssertTrue(waitForLabel(app.staticTexts["pageIndicator"], "2 / 5"))
        let canvas = app.scrollViews["noteCanvas"]
        let start = canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.40, dy: 0.40))
        let end = canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.55, dy: 0.50))
        start.press(forDuration: 0.1, thenDragTo: end)
        XCTAssertTrue(waitForLabel(app.staticTexts["strokeCount"], "획 1"))
        app.buttons["nextPage"].tap()
        XCTAssertTrue(waitForLabel(app.staticTexts["pageIndicator"], "3 / 5"))
        XCTAssertTrue(waitForLabel(app.staticTexts["strokeCount"], "획 0"))
        app.buttons["previousPage"].tap()
        XCTAssertTrue(waitForLabel(app.staticTexts["strokeCount"], "획 1"))
        XCTAssertTrue(waitForLabel(app.staticTexts["saveStatus"], "저장 완료"))
        app.terminate()
        app.launch()
        XCTAssertTrue(waitForLabel(app.staticTexts["pageIndicator"], "2 / 5"))
        XCTAssertTrue(waitForLabel(app.staticTexts["strokeCount"], "획 1"))
    }

    private func waitForLabel(_ element: XCUIElement, _ label: String) -> Bool {
        let predicate = NSPredicate(format: "label == %@", label)
        return XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: element)], timeout: 10) == .completed
    }
}
