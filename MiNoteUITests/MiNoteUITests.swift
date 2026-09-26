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

    private func waitForLabel(_ element: XCUIElement, _ label: String) -> Bool {
        let predicate = NSPredicate(format: "label == %@", label)
        return XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: element)], timeout: 10) == .completed
    }
}
