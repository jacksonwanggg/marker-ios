import XCTest

/// Walks a live unit with MARKER_QA_READONLY set, so the client refuses anything with side effects.
@MainActor
final class LiveQATests: XCTestCase {
    var app: XCUIApplication!

    override func setUp() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let token = env["MARKER_QA_TOKEN"], let user = env["MARKER_QA_USER"] else {
            throw XCTSkip("live QA needs TEST_RUNNER_MARKER_QA_TOKEN and TEST_RUNNER_MARKER_QA_USER")
        }
        continueAfterFailure = true
        app = XCUIApplication()
        app.launchEnvironment = ["MARKER_QA_TOKEN": token, "MARKER_QA_USER": user, "MARKER_QA_READONLY": "1"]
        app.launch()
    }

    private func element(containing text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    private func snap(_ name: String) {
        let a = XCTAttachment(screenshot: app.screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }

    private func tab(_ name: String) { app.tabBars.buttons[name].tap() }

    func testReadOnlyWalkthrough() throws {
        XCTAssertTrue(element(containing: "awaiting feedback").waitForExistence(timeout: 30) || element(containing: "Nothing in scope").exists,
                      "inbox summary line")
        snap("L01-inbox-mine")

        // the scope menu's button is labelled with the current scope
        app.buttons["My students"].firstMatch.tap()
        sleep(1)
        let option = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "All students")).firstMatch
        XCTAssertTrue(option.waitForExistence(timeout: 3), "All students is reachable without scrolling the menu")
        snap("L02a-scope-menu")
        option.tap()
        let loaded = NSPredicate(format: "label CONTAINS 'awaiting feedback' AND NOT (label BEGINSWITH '1 task ')")
        XCTAssertTrue(app.staticTexts.matching(loaded).firstMatch.waitForExistence(timeout: 60), "all-students inbox loaded")
        snap("L02-inbox-all")
        app.buttons["Waiting 2d+"].firstMatch.tap()
        snap("L03-inbox-waiting")
        app.buttons["Waiting 2d+"].firstMatch.tap()

        // cell 0 is the header row
        let row = app.cells.element(boundBy: 1)
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()
        XCTAssertTrue(app.buttons["Sheet"].waitForExistence(timeout: 10))
        sleep(3)
        snap("L04-task-submission")

        let sheetTab = app.buttons["Sheet"]
        sheetTab.tap()
        if !sheetTab.isSelected { sleep(1); sheetTab.tap() }
        XCTAssertTrue(sheetTab.isSelected, "Sheet tab selected")
        XCTAssertTrue(element(containing: "Page 1 of").waitForExistence(timeout: 30) || element(containing: "Details").exists, "task sheet loads")
        snap("L05-task-sheet")

        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Comments")).firstMatch.tap()
        XCTAssertTrue(element(containing: "Blocked in QA read-only mode").waitForExistence(timeout: 10), "comments fetch is blocked")
        snap("L06-task-comments-blocked")

        // the guard refuses the write, so the status should roll back with an error
        app.buttons["Set status to Complete"].tap()
        let confirm = app.buttons["Set Complete"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()
        XCTAssertTrue(element(containing: "Complete not set").waitForExistence(timeout: 5), "rollback toast")
        snap("L07-status-rolled-back")
        XCTAssertFalse(element(containing: "Status Complete").exists && !element(containing: "Complete not set").exists)

        app.navigationBars.buttons.element(boundBy: 0).tap()

        tab("Explorer")
        XCTAssertTrue(app.cells.element(boundBy: 1).waitForExistence(timeout: 30) || element(containing: "No tasks match").exists)
        XCTAssertTrue(element(containing: "· (W)").exists, "explorer opens on a weekly task")
        snap("L08-explorer")
        app.buttons["All tutorials"].firstMatch.tap()
        sleep(1)
        snap("L09-explorer-all")

        tab("Students")
        XCTAssertTrue(element(containing: "in your tutorials").waitForExistence(timeout: 20))
        snap("L10-students")
        let student = app.cells.element(boundBy: 1)
        if student.waitForExistence(timeout: 10) {
            student.tap()
            XCTAssertTrue(element(containing: "TASKS").waitForExistence(timeout: 20) || element(containing: "Tasks").exists)
            sleep(2)
            snap("L11-student")
            app.navigationBars.buttons.element(boundBy: 0).tap()
        }

        tab("Notifications")
        XCTAssertTrue(element(containing: "SUMMARY").waitForExistence(timeout: 10))
        snap("L12-notifications")

        tab("Settings")
        XCTAssertTrue(element(containing: "Signed in until").waitForExistence(timeout: 10))
        let debugRow = element(containing: "My tutorials")
        for _ in 0..<10 where !(debugRow.exists && debugRow.isHittable) { app.swipeUp() }
        snap("L13-settings")
        XCTAssertTrue(debugRow.exists, "debug section is shown")
        let csv = app.buttons["CSV exports"].firstMatch
        for _ in 0..<6 where !(csv.exists && csv.isHittable) { app.swipeDown() }
        csv.tap()
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Awaiting feedback")).firstMatch.tap()
        let shared = app.otherElements["ActivityListView"].waitForExistence(timeout: 30) || app.buttons["Copy"].waitForExistence(timeout: 5)
        XCTAssertTrue(shared, "share sheet for the CSV")
        snap("L14-csv-share")
    }

    func testSwitchingUnits() throws {
        XCTAssertTrue(element(containing: "awaiting feedback").waitForExistence(timeout: 30) || element(containing: "Nothing in scope").exists)
        app.buttons["Unit"].firstMatch.tap()
        let older = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Sep 2025")).firstMatch
        XCTAssertTrue(older.waitForExistence(timeout: 5), "an older offering is listed")
        snap("L15-unit-menu")
        older.tap()
        XCTAssertTrue(element(containing: "Sep 2025").waitForExistence(timeout: 20))
        sleep(4)
        snap("L16-older-unit")
        app.buttons["Unit"].firstMatch.tap()
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Sep 2026")).firstMatch.tap()
        XCTAssertTrue(element(containing: "Sep 2026").waitForExistence(timeout: 20))
    }
}
