import XCTest

@MainActor final class ClipboardUITests: XCTestCase {
    private let app=XCUIApplication()
    private var title=""
    private var pasteFrames=[[Double]]()
    private var canvas: XCUIElement { app.scrollViews["noteCanvas"] }
    private func drag(_ x:Double,_ y:Double,_ ex:Double,_ ey:Double) {
        canvas.coordinate(withNormalizedOffset:.init(dx:x,dy:y)).press(forDuration:0.1,thenDragTo:canvas.coordinate(withNormalizedOffset:.init(dx:ex,dy:ey)))
    }
    private func create(_ name:String) {
        title=name; XCTAssertTrue(app.buttons["newNote"].waitForExistence(timeout:15)); app.buttons["newNote"].tap()
        let field=app.textFields["nameField"]; XCTAssertTrue(field.waitForExistence(timeout:5)); field.tap(); field.typeText(title)
        app.buttons["confirmName"].tap(); XCTAssertTrue(app.buttons[title].waitForExistence(timeout:10)); app.buttons[title].tap()
        XCTAssertTrue(canvas.waitForExistence(timeout:15))
    }
    private func stage(_ phase:String,_ count:Int) throws {
        for (id,label) in [("strokeCount","획 \(count)"),("saveStatus","저장 완료")] {
            XCTAssertEqual(XCTWaiter.wait(for:[XCTNSPredicateExpectation(predicate:NSPredicate(format:"label == %@",label),object:app.staticTexts[id])],timeout:15),.completed)
        }
        print("MINOTE_CLIPBOARD_STAGE " + String(decoding:try JSONSerialization.data(withJSONObject:["title":title,"phase":phase,"count":count,"pasteFrames":pasteFrames],options:.sortedKeys),as:UTF8.self))
        let a=XCTAttachment(screenshot:app.screenshot()); a.name=phase; a.lifetime = .keepAlways; add(a)
        Thread.sleep(forTimeInterval:1)
    }
    private func copyFirst() {
        app.buttons["tool-lasso"].tap(); drag(0.4,0.2,0.4,0.4)
        XCTAssertEqual(XCTWaiter.wait(for:[XCTNSPredicateExpectation(predicate:NSPredicate(format:"label == '선택 1획'"),object:app.staticTexts["selectionCount"])],timeout:10),.completed)
        XCTAssertTrue(app.buttons["copySelectedInk"].waitForExistence(timeout:5)); app.buttons["copySelectedInk"].tap()
    }
    private func paste() {
        let page=app.descendants(matching:.any).matching(identifier:"inkCanvas").firstMatch
        XCTAssertTrue(page.waitForExistence(timeout:5),app.debugDescription)
        let v=canvas.frame, p=page.frame
        pasteFrames=[[Double(v.minX),Double(v.minY),Double(v.width),Double(v.height)],
                     [Double(p.minX),Double(p.minY),Double(p.width),Double(p.height)]]
        let control=app.buttons["pasteSelectedInk"]
        XCTAssertTrue(control.waitForExistence(timeout:10)); XCTAssertTrue(control.isEnabled); control.tap()
    }
    func testCopyToAnotherPageAndNoteNativeHistoryAndReopen() throws {
        continueAfterFailure=false; app.launch(); let suffix=String(UUID().uuidString.prefix(6))
        let sourceTitle="ClipSource-"+suffix; create(sourceTitle)
        drag(0.3,0.3,0.5,0.3); try stage("clipSource",1); copyFirst(); try stage("clipCopied",1)
        app.buttons["pageManager"].tap(); XCTAssertTrue(app.buttons["addPage"].waitForExistence(timeout:5)); app.buttons["addPage"].tap()
        let add=app.buttons["addPage-blank"]; XCTAssertTrue(add.waitForExistence(timeout:5)); add.tap()
        app.buttons["closePageManager"].tap()
        XCTAssertTrue(canvas.waitForExistence(timeout:10)); try stage("clipBlank",0)
        paste(); try stage("clipPasted",1)
        app.buttons["tool-pen"].tap(); drag(0.3,0.7,0.5,0.7); try stage("clipPen",2)
        for (phase,count) in [("clipUndoPen",1),("clipUndoPaste",0)] { app.buttons["undo"].tap(); try stage(phase,count) }
        for (phase,count) in [("clipRedoPaste",1),("clipRedoPen",2)] { app.buttons["redo"].tap(); try stage(phase,count) }
        app.terminate(); app.launch(); XCTAssertTrue(app.buttons[sourceTitle].waitForExistence(timeout:15)); app.buttons[sourceTitle].tap(); try stage("clipReopen",2)
        app.buttons["previousPage"].tap(); try stage("clipSourceAgain",1)
        app.buttons["closeNote"].tap(); create("ClipTarget-"+suffix)
        app.buttons["tool-lasso"].tap(); paste(); try stage("clipOtherNote",1)
        app.buttons["undo"].tap(); try stage("clipOtherUndo",0)
        app.buttons["redo"].tap(); try stage("clipOtherRedo",1)
    }
}
