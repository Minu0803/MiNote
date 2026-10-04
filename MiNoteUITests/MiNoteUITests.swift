import XCTest

@MainActor final class MiNoteUITests: XCTestCase {
    func testInkUndoRedoAndRelaunch() throws {
        let app = XCUIApplication()
        app.launch()
        let title = createNote(app, prefix: "Ink")
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
        openNote(app, title: title)
        XCTAssertTrue(waitForLabel(app.staticTexts["strokeCount"], expected))
    }

    func testPDFImportNavigationAndRelaunch() throws {
        let app = XCUIApplication()
        app.launch()
        let title = createNote(app, prefix: "PDF")
        XCTAssertTrue(app.buttons["importPDF"].waitForExistence(timeout: 10))
        if app.buttons["importPDF"].isEnabled {
            app.buttons["importPDF"].tap()
            let local = app.cells.matching(NSPredicate(format: "label == '나의 iPad' OR label == 'On My iPad'")).firstMatch
            guard local.waitForExistence(timeout: 30) else { XCTFail("Local Files location unavailable: \(app.debugDescription)"); return }
            local.tap()
            let folder = app.cells.matching(NSPredicate(format: "label BEGINSWITH 'MiNote'")).firstMatch
            guard folder.waitForExistence(timeout: 15) else { XCTFail("MiNote folder unavailable: \(app.debugDescription)"); return }
            folder.tap()
            let sample = app.cells.matching(NSPredicate(format: "label CONTAINS 'MiNote-Sample'")).firstMatch
            guard sample.waitForExistence(timeout: 15) else { XCTFail("PDF fixture unavailable: \(app.debugDescription)"); return }
            sample.tap()
        } else {
            for _ in 0..<5 {
                if app.staticTexts["pageIndicator"].label.split(separator: " ").first == "2" { break }
                let page = Int(app.staticTexts["pageIndicator"].label.split(separator: " ").first ?? "") ?? 1
                app.buttons[page > 2 ? "previousPage" : "nextPage"].tap()
            }
        }
        XCTAssertTrue(waitForLabel(app.staticTexts["pageIndicator"], "2 / 5"))
        let initial = Int(app.staticTexts["strokeCount"].label.split(separator: " ").last ?? "") ?? 0
        let expectedCount = "획 \(initial + 1)"
        let canvas = app.scrollViews["noteCanvas"]
        let start = canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.40, dy: 0.40))
        let end = canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.55, dy: 0.50))
        start.press(forDuration: 0.1, thenDragTo: end)
        XCTAssertTrue(waitForLabel(app.staticTexts["strokeCount"], expectedCount))
        app.buttons["undo"].tap()
        XCTAssertTrue(waitForLabel(app.staticTexts["strokeCount"], "획 \(initial)"))
        app.buttons["redo"].tap()
        XCTAssertTrue(waitForLabel(app.staticTexts["strokeCount"], expectedCount))
        canvas.pinch(withScale: 1.5, velocity: 1)
        XCTAssertTrue(waitForLabel(app.staticTexts["strokeCount"], expectedCount))
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(waitForLabel(app.staticTexts["strokeCount"], expectedCount))
        XCUIDevice.shared.orientation = .portrait
        print("MINOTE_PAGE_NAV_BEFORE",app.buttons["nextPage"].debugDescription)
        app.buttons["nextPage"].tap()
        let navigated=waitForLabel(app.staticTexts["pageIndicator"], "3 / 5")
        if !navigated {
            print("MINOTE_PAGE_NAV_FAILED",app.debugDescription)
            let failure=XCTAttachment(screenshot:app.screenshot()); failure.name="pdf-navigation-failure"; failure.lifetime = .keepAlways; add(failure)
        }
        XCTAssertTrue(navigated)
        XCTAssertTrue(waitForLabel(app.staticTexts["strokeCount"], "획 0"))
        app.buttons["previousPage"].tap()
        XCTAssertTrue(waitForLabel(app.staticTexts["strokeCount"], expectedCount))
        XCTAssertTrue(waitForLabel(app.staticTexts["saveStatus"], "저장 완료"))
        app.terminate()
        app.launch()
        openNote(app, title: title)
        XCTAssertTrue(waitForLabel(app.staticTexts["pageIndicator"], "2 / 5"))
        XCTAssertTrue(waitForLabel(app.staticTexts["strokeCount"], expectedCount))
        app.buttons["exportPDF"].tap()
        XCTAssertTrue(app.buttons["sharePDF"].waitForExistence(timeout: 20))
        let preview = XCTAttachment(screenshot: app.screenshot()); preview.lifetime = .keepAlways; add(preview)
        app.buttons["sharePDF"].tap()
        let saveFile = app.buttons.matching(NSPredicate(format: "label CONTAINS '파일에 저장' OR label CONTAINS 'Save to Files'")).firstMatch
        XCTAssertTrue(saveFile.waitForExistence(timeout: 15))
    }

    private func createNote(_ app: XCUIApplication, prefix: String) -> String {
        let title = "\(prefix)-\(UUID().uuidString.prefix(6))"
        XCTAssertTrue(app.buttons["newNote"].waitForExistence(timeout: 15))
        app.buttons["newNote"].tap()
        let field = app.textFields["nameField"]; XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap(); field.typeText(title); app.buttons["confirmName"].tap()
        openNote(app, title: title)
        return title
    }
    private func openNote(_ app: XCUIApplication, title: String) {
        XCTAssertTrue(app.buttons[title].waitForExistence(timeout: 15)); app.buttons[title].tap()
        XCTAssertTrue(app.buttons["closeNote"].waitForExistence(timeout: 15))
    }

    private func waitForLabel(_ element: XCUIElement, _ label: String) -> Bool {
        let predicate = NSPredicate(format: "label == %@", label)
        return XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: element)], timeout: 10) == .completed
    }
}
