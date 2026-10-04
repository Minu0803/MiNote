import XCTest

@MainActor final class LassoUITests: XCTestCase {
    func testNativePenMovePenUndoRedoAndRelaunch() throws {
        let app = XCUIApplication(); app.launch()
        let title = "Lasso-" + UUID().uuidString.prefix(6)
        XCTAssertTrue(app.buttons["newNote"].waitForExistence(timeout: 15)); app.buttons["newNote"].tap()
        let name = app.textFields["nameField"]; XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap(); name.typeText(title); app.buttons["confirmName"].tap()
        XCTAssertTrue(app.buttons[title].waitForExistence(timeout: 10)); app.buttons[title].tap()
        let canvas = app.scrollViews["noteCanvas"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 15))
        func drag(_ x: Double, _ y: Double, _ ex: Double, _ ey: Double) {
            canvas.coordinate(withNormalizedOffset: CGVector(dx: x,dy: y)).press(forDuration: 0.1,
                thenDragTo: canvas.coordinate(withNormalizedOffset: CGVector(dx: ex,dy: ey)))
        }
        func stage(_ phase: String, count: Int) throws {
            let strokeCount = app.staticTexts["strokeCount"], save = app.staticTexts["saveStatus"]
            let countMatches = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "획 \(count)"), object: strokeCount).wait(15)
            XCTAssertTrue(countMatches,strokeCount.label)
            guard countMatches else { throw LassoTestError.unexpectedInk }
            let saved = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == '저장 완료'"), object: save).wait(15)
            XCTAssertTrue(saved,save.label)
            guard saved else { throw LassoTestError.unsaved }
            let data = try JSONSerialization.data(withJSONObject: ["title":title,"phase":phase,"count":count],options:.sortedKeys)
            print("MINOTE_LASSO_STAGE " + String(decoding:data,as:UTF8.self))
            let image = XCTAttachment(screenshot: app.screenshot()); image.name = "lasso-" + phase; image.lifetime = .keepAlways; add(image)
            // Give the external read-only observer time to retain the saved document at this boundary.
            Thread.sleep(forTimeInterval: 1)
        }
        drag(0.30,0.30,0.50,0.30); try stage("pen1",count:1)
        let lasso = app.buttons["tool-lasso"]
        guard lasso.waitForExistence(timeout: 10) else { XCTFail("Lasso tool unavailable: \(app.debugDescription)"); return }
        lasso.tap()
        // A straight boundary sweep is a closed degenerate lasso; it crosses the ink centre line.
        drag(0.40,0.20,0.40,0.40)
        let selected = app.staticTexts["selectionCount"]
        XCTAssertTrue(XCTNSPredicateExpectation(predicate:NSPredicate(format:"label == '선택 1획'"),object:selected).wait(10))
        drag(0.40,0.30,0.55,0.45); try stage("move1",count:1)
        app.buttons["tool-pen"].tap()
        drag(0.30,0.65,0.50,0.65); try stage("pen2",count:2)
        for (phase,count) in [("undoPen2",1),("undoMove",1),("undoPen1",0)] {
            XCTAssertTrue(app.buttons["undo"].isEnabled); app.buttons["undo"].tap(); try stage(phase,count:count)
        }
        for (phase,count) in [("redoPen1",1),("redoMove",1),("redoPen2",2)] {
            XCTAssertTrue(app.buttons["redo"].isEnabled); app.buttons["redo"].tap(); try stage(phase,count:count)
        }
        app.buttons["tool-eraser"].tap()
        drag(0.55,0.35,0.55,0.55); try stage("eraseMoved",count:1)
        app.buttons["undo"].tap(); try stage("undoErase",count:2)
        app.buttons["redo"].tap(); try stage("redoErase",count:1)
        app.buttons["undo"].tap(); try stage("restoreErase",count:2)
        app.buttons["tool-lasso"].tap()
        canvas.pinch(withScale:1.5,velocity:1); try stage("zoom",count:2)
        XCUIDevice.shared.orientation = .landscapeLeft; try stage("rotation",count:2)
        XCUIDevice.shared.orientation = .portrait; try stage("portrait",count:2)
        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons[title].waitForExistence(timeout: 15)); app.buttons[title].tap()
        try stage("relaunch",count:2)
    }
    func testRotatedPDFLassoMoveZoomAndExport() throws {
        continueAfterFailure=false
        let app=XCUIApplication(); app.launch()
        let title="LassoPDF-" + UUID().uuidString.prefix(6)
        XCTAssertTrue(app.buttons["newNote"].waitForExistence(timeout:15)); app.buttons["newNote"].tap()
        let name=app.textFields["nameField"]; XCTAssertTrue(name.waitForExistence(timeout:5))
        name.tap(); name.typeText(title); app.buttons["confirmName"].tap()
        XCTAssertTrue(app.buttons[title].waitForExistence(timeout:10)); app.buttons[title].tap()
        XCTAssertTrue(app.buttons["importPDF"].waitForExistence(timeout:15)); app.buttons["importPDF"].tap()
        let sample=app.cells.matching(NSPredicate(format:"label CONTAINS 'MiNote-Second' AND NOT label CONTAINS 'minote'")).firstMatch
        if !sample.waitForExistence(timeout:2) {
            let local=app.cells.matching(NSPredicate(format:"label == '나의 iPad' OR label == 'On My iPad'")).firstMatch
            XCTAssertTrue(local.waitForExistence(timeout:20)); local.tap()
            let folder=app.cells.matching(NSPredicate(format:"label BEGINSWITH 'MiNote'")).firstMatch
            XCTAssertTrue(folder.waitForExistence(timeout:10)); folder.tap()
        }
        XCTAssertTrue(sample.waitForExistence(timeout:10)); sample.tap()
        XCTAssertTrue(XCTNSPredicateExpectation(predicate:NSPredicate(format:"label == '2 / 2'"),object:app.staticTexts["pageIndicator"]).wait(15))
        let canvas=app.scrollViews["noteCanvas"]
        func drag(_ x: Double,_ y: Double,_ ex: Double,_ ey: Double) {
            canvas.coordinate(withNormalizedOffset:CGVector(dx:x,dy:y)).press(forDuration:0.1,
                thenDragTo:canvas.coordinate(withNormalizedOffset:CGVector(dx:ex,dy:ey)))
        }
        func stage(_ phase: String) throws {
            XCTAssertTrue(XCTNSPredicateExpectation(predicate:NSPredicate(format:"label == '획 1'"),object:app.staticTexts["strokeCount"]).wait(15))
            XCTAssertTrue(XCTNSPredicateExpectation(predicate:NSPredicate(format:"label == '저장 완료'"),object:app.staticTexts["saveStatus"]).wait(15))
            let data=try JSONSerialization.data(withJSONObject:["title":title,"phase":phase,"count":1],options:.sortedKeys)
            print("MINOTE_LASSO_STAGE " + String(decoding:data,as:UTF8.self))
            let image=XCTAttachment(screenshot:app.screenshot()); image.name="lasso-"+phase; image.lifetime = .keepAlways; add(image)
            Thread.sleep(forTimeInterval:1)
        }
        drag(0.30,0.50,0.50,0.50); try stage("pdfPen")
        app.buttons["tool-lasso"].tap(); drag(0.40,0.35,0.40,0.65)
        XCTAssertTrue(XCTNSPredicateExpectation(predicate:NSPredicate(format:"label == '선택 1획'"),object:app.staticTexts["selectionCount"]).wait(10))
        drag(0.40,0.50,0.55,0.60); try stage("pdfMove")
        canvas.pinch(withScale:1.5,velocity:1); try stage("pdfZoom")
        app.terminate(); app.launch(); XCTAssertTrue(app.buttons[title].waitForExistence(timeout:15)); app.buttons[title].tap()
        try stage("pdfRelaunch")
        app.buttons["exportPDF"].tap(); XCTAssertTrue(app.buttons["sharePDF"].waitForExistence(timeout:30))
        let preview=XCTAttachment(screenshot:app.screenshot()); preview.name="lasso-pdf-export"; preview.lifetime = .keepAlways; add(preview)
    }
}
private enum LassoTestError: Error { case unexpectedInk, unsaved }

private extension XCTNSPredicateExpectation {
    func wait(_ timeout: TimeInterval) -> Bool { XCTWaiter.wait(for:[self],timeout:timeout) == .completed }
}
