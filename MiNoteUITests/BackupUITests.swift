import XCTest

@MainActor final class BackupUITests: XCTestCase {
    func testBackupExportViaFilesAndDuplicateRestore() {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launch()
        let suffix = UUID().uuidString.prefix(6), title = "Backup-\(suffix)", filename = "Backup-\(suffix)"
        create(app, title: title); app.buttons[title].tap()
        XCTAssertTrue(app.staticTexts["strokeCount"].waitForExistence(timeout: 15)); draw(app)
        XCTAssertTrue(wait(app.staticTexts["strokeCount"], "획 1"))
        app.buttons["pageManager"].tap(); app.buttons["addPage"].tap(); app.buttons["addPage-ruled"].tap()
        app.buttons["closePageManager"].tap(); draw(app); XCTAssertTrue(wait(app.staticTexts["strokeCount"], "획 1"))
        app.buttons["pageManager"].tap(); app.buttons["pageActions-2"].tap(); app.buttons["bookmarkPage"].tap()
        app.buttons["pageActions-2"].tap(); app.buttons["duplicatePage"].tap()
        XCTAssertTrue(app.buttons["pageActions-3"].waitForExistence(timeout: 5))
        app.buttons["pageActions-2"].tap(); app.buttons["deletePage"].tap()
        confirm(app, id: "confirmDeletePage")
        app.buttons["closePageManager"].tap(); XCTAssertTrue(wait(app.staticTexts["pageIndicator"], "2 / 2"))
        pick(app, button: "importPDF", filename: "MiNote-Sample")
        XCTAssertTrue(wait(app.staticTexts["pageIndicator"], "3 / 6")); draw(app)
        XCTAssertTrue(wait(app.staticTexts["strokeCount"], "획 1"))
        pick(app, button: "importPDF", filename: "MiNote-Second")
        XCTAssertTrue(wait(app.staticTexts["pageIndicator"], "4 / 7")); draw(app)
        XCTAssertTrue(wait(app.staticTexts["strokeCount"], "획 1"))
        app.buttons["exportBackup"].tap(); XCTAssertTrue(app.buttons["shareBackup"].waitForExistence(timeout: 30))
        app.buttons["shareBackup"].tap(); saveToFiles(app, filename: filename)
        tapHittable(app.buttons["closeExportPreview"], app: app)
        tapHittable(app.buttons["closeNote"], app: app)
        pick(app, button: "restoreBackup", filename: filename)
        let restored = title + " (복원)"
        XCTAssertTrue(app.buttons[restored].waitForExistence(timeout: 30)); XCTAssertTrue(app.buttons[title].exists)
        app.buttons[restored].tap(); XCTAssertTrue(wait(app.staticTexts["pageIndicator"], "4 / 7"))
        XCTAssertTrue(wait(app.staticTexts["strokeCount"], "획 1")); draw(app)
        XCTAssertTrue(wait(app.staticTexts["strokeCount"], "획 2")); app.buttons["undo"].tap()
        XCTAssertTrue(wait(app.staticTexts["strokeCount"], "획 1")); app.buttons["redo"].tap()
        XCTAssertTrue(wait(app.staticTexts["strokeCount"], "획 2")); XCTAssertTrue(wait(app.staticTexts["saveStatus"], "저장 완료"))
        app.terminate(); app.launch(); XCTAssertTrue(app.buttons[restored].waitForExistence(timeout: 15)); app.buttons[restored].tap()
        XCTAssertTrue(wait(app.staticTexts["strokeCount"], "획 2"))
        print("MINOTE_BACKUP_FILE=\(filename).minote TITLE=\(title)")
        let image = XCTAttachment(screenshot: app.screenshot()); image.lifetime = .keepAlways; add(image)
    }

    func testBackupTransferIntoEmptyInstallation() throws {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launch(); XCTAssertTrue(app.buttons["newNote"].waitForExistence(timeout: 15))
        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'note-'"))
        try XCTSkipUnless(rows.count == 0, "Use a new isolated Backup simulator with transferred Transfer.minote.")
        pick(app, button: "restoreBackup", filename: "Transfer.minote")
        let restored = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'note-' AND label BEGINSWITH 'Backup-' AND label ENDSWITH ' (복원)'" )).firstMatch
        XCTAssertTrue(restored.waitForExistence(timeout: 30), app.debugDescription); XCTAssertEqual(rows.count, 1)
        let title = restored.label; restored.tap()
        XCTAssertTrue(wait(app.staticTexts["pageIndicator"], "4 / 7")); XCTAssertTrue(wait(app.staticTexts["strokeCount"], "획 1"))
        app.buttons["previousPage"].tap(); XCTAssertTrue(wait(app.staticTexts["strokeCount"], "획 1"))
        app.buttons["nextPage"].tap(); draw(app); XCTAssertTrue(wait(app.staticTexts["strokeCount"], "획 2"))
        app.buttons["undo"].tap(); XCTAssertTrue(wait(app.staticTexts["strokeCount"], "획 1"))
        app.buttons["redo"].tap(); XCTAssertTrue(wait(app.staticTexts["strokeCount"], "획 2"))
        XCTAssertTrue(wait(app.staticTexts["saveStatus"], "저장 완료")); app.terminate(); app.launch()
        XCTAssertTrue(app.buttons[title].waitForExistence(timeout: 15)); app.buttons[title].tap()
        XCTAssertTrue(wait(app.staticTexts["strokeCount"], "획 2")); XCTAssertTrue(wait(app.staticTexts["pageIndicator"], "4 / 7"))
    }

    func testPermanentDeletionRequiresConfirmation() {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launch(); let title = "Purge-\(UUID().uuidString.prefix(6))"
        create(app, title: title); app.buttons[title].tap()
        XCTAssertTrue(app.buttons["pageManager"].waitForExistence(timeout: 10)); app.buttons["pageManager"].tap()
        app.buttons["addPage"].tap(); app.buttons["addPage-grid"].tap()
        app.buttons["pageActions-2"].tap(); app.buttons["deletePage"].tap()
        confirm(app, id: "confirmDeletePage")
        app.buttons["filter-pages-deleted"].tap()
        let purgePage = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'purgePage-'" )).firstMatch
        XCTAssertTrue(purgePage.waitForExistence(timeout: 5)); purgePage.tap(); app.alerts.buttons["취소"].tap()
        XCTAssertTrue(purgePage.exists); purgePage.tap(); confirm(app, id: "confirmPurgePage")
        XCTAssertTrue(app.staticTexts["삭제한 페이지가 없습니다."].waitForExistence(timeout: 5))
        app.buttons["closePageManager"].tap(); app.buttons["closeNote"].tap()
        XCTAssertTrue(app.buttons["노트 관리 \(title)"].waitForExistence(timeout: 10)); app.buttons["노트 관리 \(title)"].tap(); app.buttons["trashNote"].tap()
        app.buttons["filter-trash"].tap()
        let note = app.buttons[title]; XCTAssertTrue(note.waitForExistence(timeout: 5))
        let row = note.parentCell(in: app)
        let purge = row.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'purgeNote-'" )).firstMatch
        XCTAssertTrue(purge.exists); purge.tap(); app.alerts.buttons["취소"].tap(); XCTAssertTrue(note.exists)
        purge.tap(); confirm(app, id: "confirmPurgeNote")
        XCTAssertTrue(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: note)], timeout: 10) == .completed)
        app.buttons["storageMaintenance"].tap(); XCTAssertTrue(app.buttons["cleanStorage"].waitForExistence(timeout: 15))
        app.buttons["cleanStorage"].tap(); app.alerts.buttons["취소"].tap()
        XCTAssertTrue(app.buttons["cleanStorage"].exists); app.buttons["cleanStorage"].tap()
        confirm(app, id: "confirmCleanup")
        XCTAssertTrue(app.staticTexts["cleanupResult"].waitForExistence(timeout: 10)); app.buttons["closeStorage"].tap()
    }
    private func confirm(_ app: XCUIApplication, id: String) {
        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        let button = alert.buttons.matching(identifier: id).firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 5), app.debugDescription)
        button.tap()
        XCTAssertTrue(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: alert)], timeout: 5) == .completed, app.debugDescription)
    }
    private func tapHittable(_ element: XCUIElement, app: XCUIApplication) {
        XCTAssertTrue(element.waitForExistence(timeout: 15), app.debugDescription)
        let predicate = NSPredicate { _, _ in element.isHittable && element.isEnabled }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: element)], timeout: 15), .completed, app.debugDescription)
        element.tap()
    }
    private func create(_ app: XCUIApplication, title: String) {
        XCTAssertTrue(app.buttons["newNote"].waitForExistence(timeout: 15)); app.buttons["newNote"].tap()
        let name = app.textFields["nameField"]; XCTAssertTrue(name.waitForExistence(timeout: 5)); name.tap(); name.typeText(title)
        app.buttons["confirmName"].tap(); XCTAssertTrue(app.buttons[title].waitForExistence(timeout: 10))
    }
    private func draw(_ app: XCUIApplication) {
        let canvas = app.scrollViews["noteCanvas"]
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.4, dy: 0.3)).press(forDuration: 0.1,
            thenDragTo: canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.55, dy: 0.4)))
    }
    private func pick(_ app: XCUIApplication, button: String, filename: String) {
        XCTAssertTrue(app.buttons[button].waitForExistence(timeout: 5))
        app.buttons[button].tap()
        let file = app.cells.matching(NSPredicate(format: "label CONTAINS %@", filename)).firstMatch
        if !file.waitForExistence(timeout: 2) {
            let local = app.cells.matching(NSPredicate(format: "label == '나의 iPad' OR label == 'On My iPad'")).firstMatch
            guard local.waitForExistence(timeout: 15) else { XCTFail("Files: \(app.debugDescription)"); return }
            local.tap()
            let folder = app.cells.matching(NSPredicate(format: "label BEGINSWITH 'MiNote'")).firstMatch
            XCTAssertTrue(folder.waitForExistence(timeout: 10)); folder.tap()
        }
        XCTAssertTrue(file.waitForExistence(timeout: 10), app.debugDescription); file.tap()
    }
    private func saveToFiles(_ app: XCUIApplication, filename: String) {
        let save = app.cells.matching(NSPredicate(format: "label == 'Save to Files' OR label == '파일에 저장'" )).firstMatch
        guard save.waitForExistence(timeout: 10) else { XCTFail("Share: \(app.debugDescription)"); return }; save.tap()
        let field = app.textFields.firstMatch
        guard field.waitForExistence(timeout: 20) else { XCTFail("Save dialog: \(app.debugDescription)"); return }
        field.tap(); let length = (field.value as? String)?.count ?? 0
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: length) + filename)
        let local = app.cells.matching(NSPredicate(format: "label == '나의 iPad' OR label == 'On My iPad'")).firstMatch
        if local.exists {
            tapHittable(local, app: app)
            // The activity sheet's hidden shareCell is also labelled MiNote.
            // Resolve the destination only inside Files' actual file list.
            let folder = app.collectionViews["File View"].cells.matching(NSPredicate(format: "label == 'MiNote' OR label BEGINSWITH 'MiNote,'")).firstMatch
            tapHittable(folder, app: app)
        }
        let saveButton = app.navigationBars.buttons.matching(NSPredicate(format: "label == 'Save' OR label == '저장'" )).firstMatch
        tapHittable(saveButton, app: app)
    }
    private func wait(_ element: XCUIElement, _ label: String) -> Bool {
        XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", label), object: element)], timeout: 10) == .completed
    }
}
private extension XCUIElement {
    func parentCell(in app: XCUIApplication) -> XCUIElement {
        app.cells.containing(.button, identifier: identifier).firstMatch
    }
}
