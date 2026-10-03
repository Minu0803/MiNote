import XCTest

@MainActor final class PageManagerUITests: XCTestCase {
    func testPagesAndTwoPDFsSurviveRelaunchAndExport() {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launch()
        let title = "Pages-\(UUID().uuidString.prefix(6))"
        XCTAssertTrue(app.buttons["newNote"].waitForExistence(timeout: 15)); app.buttons["newNote"].tap()
        let name = app.textFields["nameField"]; XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap(); name.typeText(title); app.buttons["confirmName"].tap()
        XCTAssertTrue(app.buttons[title].waitForExistence(timeout: 10)); app.buttons[title].tap()
        XCTAssertTrue(app.staticTexts["strokeCount"].waitForExistence(timeout: 15))
        draw(app); XCTAssertTrue(wait(app.staticTexts["strokeCount"], "획 1"))
        manager(app); app.buttons["addPage"].tap(); app.buttons["addPage-ruled"].tap()
        closeManager(app); XCTAssertTrue(wait(app.staticTexts["pageIndicator"], "2 / 2"))
        XCTAssertTrue(wait(app.staticTexts["paperStyle"], "줄 용지")); draw(app)
        XCTAssertTrue(wait(app.staticTexts["strokeCount"], "획 1"))
        manager(app); app.buttons["addPage"].tap(); app.buttons["addPage-grid"].tap()
        closeManager(app); XCTAssertTrue(wait(app.staticTexts["paperStyle"], "격자 용지"))
        manager(app); app.buttons["pageActions-2"].tap(); app.buttons["duplicatePage"].tap()
        XCTAssertTrue(app.buttons["pageActions-4"].waitForExistence(timeout: 5))
        app.buttons["pageActions-3"].tap(); app.buttons["movePageUp"].tap()
        app.buttons["pageActions-2"].tap(); app.buttons["bookmarkPage"].tap()
        app.buttons["filter-pages-bookmarked"].tap()
        XCTAssertTrue(app.buttons["selectPage-2"].waitForExistence(timeout: 5)); XCTAssertFalse(app.buttons["selectPage-1"].exists)
        app.buttons["filter-pages-all"].tap()
        app.buttons["pageActions-2"].tap(); app.buttons["deletePage"].tap()
        let confirmation = app.alerts["페이지를 삭제할까요?"].buttons.matching(identifier: "confirmDeletePage").firstMatch
        XCTAssertTrue(confirmation.waitForExistence(timeout: 5)); confirmation.tap()
        app.buttons["filter-pages-deleted"].tap()
        let restore = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'restorePage-'")).firstMatch
        XCTAssertTrue(restore.waitForExistence(timeout: 5)); restore.tap()
        app.buttons["filter-pages-all"].tap(); closeManager(app)
        XCTAssertTrue(wait(app.staticTexts["pageIndicator"], "2 / 4")); XCTAssertTrue(wait(app.staticTexts["strokeCount"], "획 1"))
        importPDF(app, filename: "MiNote-Sample")
        XCTAssertTrue(wait(app.staticTexts["pageIndicator"], "3 / 8")); draw(app)
        XCTAssertTrue(wait(app.staticTexts["strokeCount"], "획 1"))
        importPDF(app, filename: "MiNote-Second")
        XCTAssertTrue(wait(app.staticTexts["pageIndicator"], "4 / 9"))
        XCTAssertTrue(wait(app.staticTexts["saveStatus"], "저장 완료"))
        app.terminate(); app.launch(); XCTAssertTrue(app.buttons[title].waitForExistence(timeout: 15)); app.buttons[title].tap()
        XCTAssertTrue(wait(app.staticTexts["pageIndicator"], "4 / 9"))
        app.buttons["previousPage"].tap(); XCTAssertTrue(wait(app.staticTexts["pageIndicator"], "3 / 9"))
        XCTAssertTrue(wait(app.staticTexts["strokeCount"], "획 1"))
        app.buttons["exportPDF"].tap(); XCTAssertTrue(app.buttons["sharePDF"].waitForExistence(timeout: 30))
        let screenshot = XCTAttachment(screenshot: app.screenshot()); screenshot.lifetime = .keepAlways; add(screenshot)
    }
    private func manager(_ app: XCUIApplication) {
        XCTAssertTrue(app.buttons["pageManager"].waitForExistence(timeout: 5)); app.buttons["pageManager"].tap()
        XCTAssertTrue(app.buttons["addPage"].waitForExistence(timeout: 5))
    }
    private func closeManager(_ app: XCUIApplication) { app.buttons["closePageManager"].tap() }
    private func draw(_ app: XCUIApplication) {
        let canvas = app.scrollViews["noteCanvas"]
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.4, dy: 0.3)).press(forDuration: 0.1,
            thenDragTo: canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.55, dy: 0.4)))
    }
    private func importPDF(_ app: XCUIApplication, filename: String) {
        app.buttons["importPDF"].tap()
        let sample = app.cells.matching(NSPredicate(format: "label CONTAINS %@", filename)).firstMatch
        if !sample.waitForExistence(timeout: 2) {
            let local = app.cells.matching(NSPredicate(format: "label == '나의 iPad' OR label == 'On My iPad'")).firstMatch
            XCTAssertTrue(local.waitForExistence(timeout: 20)); local.tap()
            let folder = app.cells.matching(NSPredicate(format: "label BEGINSWITH 'MiNote'")).firstMatch
            XCTAssertTrue(folder.waitForExistence(timeout: 10)); folder.tap()
        }
        XCTAssertTrue(sample.waitForExistence(timeout: 10)); sample.tap()
    }
    private func wait(_ element: XCUIElement, _ label: String) -> Bool {
        XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", label), object: element)], timeout: 10) == .completed
    }
}
