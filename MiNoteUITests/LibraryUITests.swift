import XCTest

@MainActor final class LibraryUITests: XCTestCase {
    func testCreateOrganizeTrashRestoreAndRelaunch() {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launch()
        XCTAssertTrue(app.buttons["newNote"].waitForExistence(timeout: 15))
        let suffix = UUID().uuidString.prefix(6)
        let a = "A-\(suffix)", b = "B-\(suffix)", folder = "Work-\(suffix)", renamed = "Notes-\(suffix)"
        create(app, button: "newNote", name: a)
        create(app, button: "newNote", name: b)
        create(app, button: "newFolder", name: folder)
        app.buttons["노트 관리 \(a)"].tap(); app.buttons["moveNote"].tap()
        tapScrolling(app, button: app.buttons["대상 폴더 \(folder)"], listID: "moveDestinations")
        tapScrolling(app, button: app.buttons[folder], listID: "libraryFolders")
        XCTAssertTrue(app.buttons[a].waitForExistence(timeout: 10)); XCTAssertFalse(app.buttons[b].exists)
        app.buttons["폴더 관리 \(folder)"].tap(); app.buttons["renameFolder"].tap(); name(app, renamed)
        app.buttons[a].tap()
        XCTAssertTrue(app.staticTexts["strokeCount"].waitForExistence(timeout: 10))
        let canvas = app.scrollViews["noteCanvas"]
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.3)).press(forDuration: 0.1,
            thenDragTo: canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4)))
        XCTAssertTrue(wait(app.staticTexts["strokeCount"], "획 1"))
        // Close immediately after ink: the library must await the outgoing save.
        app.buttons["closeNote"].tap()
        XCTAssertTrue(app.buttons["filter-all"].waitForExistence(timeout: 10)); app.buttons["filter-all"].tap()
        app.buttons[b].tap(); XCTAssertTrue(wait(app.staticTexts["strokeCount"], "획 0"))
        app.buttons["closeNote"].tap(); XCTAssertTrue(app.buttons[a].waitForExistence(timeout: 10))
        app.buttons[a].tap(); XCTAssertTrue(wait(app.staticTexts["strokeCount"], "획 1"))
        app.buttons["closeNote"].tap(); XCTAssertTrue(app.buttons["노트 관리 \(a)"].waitForExistence(timeout: 10))
        app.buttons["노트 관리 \(a)"].tap(); app.buttons["trashNote"].tap()
        XCTAssertTrue(app.buttons["filter-trash"].waitForExistence(timeout: 5)); app.buttons["filter-trash"].tap()
        XCTAssertTrue(app.buttons["복원 \(a)"].waitForExistence(timeout: 10)); app.buttons["복원 \(a)"].tap()
        tapScrolling(app, button: app.buttons[renamed], listID: "libraryFolders"); XCTAssertTrue(app.buttons[a].waitForExistence(timeout: 10))
        app.terminate(); app.launch()
        tapScrolling(app, button: app.buttons[renamed], listID: "libraryFolders")
        XCTAssertTrue(app.buttons[a].waitForExistence(timeout: 10)); XCTAssertFalse(app.buttons[b].exists)
        app.buttons[a].tap(); XCTAssertTrue(wait(app.staticTexts["strokeCount"], "획 1"))
        let screenshot = XCTAttachment(screenshot: app.screenshot()); screenshot.lifetime = .keepAlways; add(screenshot)
    }
    func testDuplicateFolderDestinationsAreDistinguishable() {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launch()
        XCTAssertTrue(app.buttons["newNote"].waitForExistence(timeout: 15))
        let suffix = UUID().uuidString.prefix(6), twin = "Twin-\(suffix)", note = "Move-\(suffix)"
        create(app, button: "newFolder", name: twin)
        create(app, button: "newFolder", name: twin)
        let folders = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'folder-' AND label BEGINSWITH %@", twin))
        let list = app.collectionViews["libraryFolders"]
        for _ in 0..<20 { if folders.count == 2 { break }; list.swipeUp() }
        XCTAssertEqual(folders.count, 2)
        let first = folders.element(boundBy: 0).label, second = folders.element(boundBy: 1).label
        XCTAssertNotEqual(first, second, "Same-name folders need stable visible and accessible distinctions")
        create(app, button: "newNote", name: note)
        app.buttons["노트 관리 \(note)"].tap(); app.buttons["moveNote"].tap()
        tapScrolling(app, button: app.buttons["대상 폴더 \(second)"], listID: "moveDestinations")
        tapScrolling(app, button: app.buttons[second], listID: "libraryFolders"); XCTAssertTrue(app.buttons[note].waitForExistence(timeout: 10))
        tapScrolling(app, button: app.buttons[first], listID: "libraryFolders"); XCTAssertFalse(app.buttons[note].exists)
    }

    func testLegacyMigrationInSeededSimulator() throws {
        let app = XCUIApplication(); app.launch()
        XCTAssertTrue(app.buttons["newNote"].waitForExistence(timeout: 15))
        let legacy = app.buttons["MiNote portable ink fixture"]
        try XCTSkipUnless(legacy.exists, "Run with a seeded isolated simulator; fixture setup is documented in PROGRESS.")
        XCTAssertTrue(app.otherElements["libraryRecovery"].exists || app.staticTexts["libraryRecovery"].exists)
        legacy.tap()
        XCTAssertTrue(wait(app.staticTexts["pageIndicator"], "1 / 5"))
        XCTAssertTrue(wait(app.staticTexts["strokeCount"], "획 4"))
        app.buttons["nextPage"].tap()
        XCTAssertTrue(wait(app.staticTexts["pageIndicator"], "2 / 5"))
        XCTAssertTrue(app.buttons["exportPDF"].isEnabled)
        app.buttons["closeNote"].tap()
        app.terminate(); app.launch()
        XCTAssertTrue(legacy.waitForExistence(timeout: 15)); legacy.tap()
        XCTAssertTrue(wait(app.staticTexts["pageIndicator"], "2 / 5"))
    }

    private func tapScrolling(_ app: XCUIApplication, button: XCUIElement, listID: String) {
        let list = app.collectionViews[listID]
        XCTAssertTrue(list.waitForExistence(timeout: 10))
        // A fresh move sheet starts at the top. Pulling down there dismisses it.
        // The persistent sidebar can start at any offset, so return it to the top first.
        if listID == "libraryFolders" {
            var previous: String?
            for _ in 0..<20 {
                if button.exists && button.isHittable { button.tap(); return }
                let visible = list.buttons.allElementsBoundByIndex.filter(\.isHittable).map(\.label).joined(separator: "|")
                if visible == previous { break }; previous = visible
                list.swipeDown()
            }
        }
        for _ in 0..<30 { if button.exists && button.isHittable { button.tap(); return }; list.swipeUp() }
        XCTFail("Target is not reachable in \(listID): \(button)")
    }

    private func create(_ app: XCUIApplication, button: String, name value: String) {
        app.buttons[button].tap(); name(app, value)
    }
    private func name(_ app: XCUIApplication, _ value: String) {
        let field = app.textFields["nameField"]; XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        if let current = field.value as? String, !current.isEmpty, current != "이름" {
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count))
        }
        field.typeText(value); app.buttons["confirmName"].tap()
        XCTAssertTrue(app.buttons["newNote"].waitForExistence(timeout: 10))
    }
    private func wait(_ element: XCUIElement, _ label: String) -> Bool {
        XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", label), object: element)], timeout: 10) == .completed
    }
}
