import XCTest

@MainActor final class SelectionCommandUITests: XCTestCase {
    private let app = XCUIApplication()
    private var title = ""
    private var canvas: XCUIElement { app.scrollViews["noteCanvas"] }
    private func start(_ prefix: String) {
        continueAfterFailure = false
        app.launch(); title = prefix + UUID().uuidString.prefix(6)
        XCTAssertTrue(app.buttons["newNote"].waitForExistence(timeout:15)); app.buttons["newNote"].tap()
        let field=app.textFields["nameField"]; XCTAssertTrue(field.waitForExistence(timeout:5))
        field.tap(); field.typeText(title); app.buttons["confirmName"].tap()
        XCTAssertTrue(app.buttons[title].waitForExistence(timeout:10)); app.buttons[title].tap()
        XCTAssertTrue(canvas.waitForExistence(timeout:15))
    }
    private func drag(_ x: Double,_ y: Double,_ ex: Double,_ ey: Double) {
        canvas.coordinate(withNormalizedOffset:CGVector(dx:x,dy:y)).press(forDuration:0.1,
            thenDragTo:canvas.coordinate(withNormalizedOffset:CGVector(dx:ex,dy:ey)))
    }
    private func selectFirst() {
        app.buttons["tool-lasso"].tap(); drag(0.40,0.20,0.40,0.40)
        XCTAssertTrue(XCTWaiter.wait(for:[XCTNSPredicateExpectation(predicate:NSPredicate(format:"label == '선택 1획'"),object:app.staticTexts["selectionCount"])],timeout:10) == .completed)
    }
    private func stage(_ phase: String,_ count: Int) throws {
        for (id,label) in [("strokeCount","획 \(count)"),("saveStatus","저장 완료")] {
            XCTAssertTrue(XCTWaiter.wait(for:[XCTNSPredicateExpectation(predicate:NSPredicate(format:"label == %@",label),object:app.staticTexts[id])],timeout:15) == .completed,app.staticTexts[id].label)
        }
        let data=try JSONSerialization.data(withJSONObject:["title":title,"phase":phase,"count":count],options:.sortedKeys)
        print("MINOTE_SELECTION_STAGE " + String(decoding:data,as:UTF8.self))
        let image=XCTAttachment(screenshot:app.screenshot()); image.name=phase; image.lifetime = .keepAlways; add(image)
        Thread.sleep(forTimeInterval:1)
    }
    func testPenDuplicatePenUndoRedoAndReopen() throws {
        start("Duplicate-")
        drag(0.30,0.30,0.50,0.30); try stage("dupPen1",1)
        selectFirst()
        let duplicate=app.buttons["duplicateSelectedInk"]
        XCTAssertTrue(duplicate.waitForExistence(timeout:5)); XCTAssertTrue(duplicate.isEnabled); duplicate.tap()
        try stage("dupClone",2)
        XCTAssertEqual(app.staticTexts["selectionCount"].label,"선택 1획")
        app.buttons["tool-pen"].tap(); drag(0.30,0.65,0.50,0.65); try stage("dupPen2",3)
        for (phase,count) in [("dupUndoPen2",2),("dupUndoClone",1),("dupUndoPen1",0)] {
            app.buttons["undo"].tap(); try stage(phase,count)
        }
        for (phase,count) in [("dupRedoPen1",1),("dupRedoClone",2),("dupRedoPen2",3)] {
            app.buttons["redo"].tap(); try stage(phase,count)
        }
        app.terminate(); app.launch(); XCTAssertTrue(app.buttons[title].waitForExistence(timeout:15)); app.buttons[title].tap()
        try stage("dupReopen",3)
    }
    func testPenDeleteUndoRedoThenPenEraserUndo() throws {
        start("Delete-")
        drag(0.30,0.30,0.50,0.30); try stage("delPen1",1)
        selectFirst()
        let delete=app.buttons["deleteSelectedInk"]
        XCTAssertTrue(delete.waitForExistence(timeout:5)); XCTAssertTrue(delete.isEnabled); delete.tap()
        try stage("delDelete",0); XCTAssertEqual(app.staticTexts["selectionCount"].label,"선택 0획")
        app.buttons["undo"].tap(); try stage("delUndo",1)
        app.buttons["redo"].tap(); try stage("delRedo",0)
        app.buttons["tool-pen"].tap(); drag(0.30,0.65,0.50,0.65); try stage("delPen2",1)
        app.buttons["tool-eraser"].tap(); drag(0.40,0.55,0.40,0.75); try stage("delErase",0)
        app.buttons["undo"].tap(); try stage("delUndoErase",1)
        app.buttons["undo"].tap(); try stage("delUndoPen2",0)
        app.buttons["undo"].tap(); try stage("delUndoDelete",1)
        app.buttons["redo"].tap(); try stage("delRedoDelete",0)
        app.buttons["redo"].tap(); try stage("delRedoPen2",1)
        app.terminate(); app.launch(); XCTAssertTrue(app.buttons[title].waitForExistence(timeout:15)); app.buttons[title].tap()
        try stage("delReopen",1)
    }
}
