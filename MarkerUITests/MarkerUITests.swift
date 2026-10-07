import XCTest

@MainActor
final class MarkerUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-demo", "YES"]
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

    func testMarkTask() throws {
        let row = element(containing: "Priya Raman")
        XCTAssertTrue(row.waitForExistence(timeout: 8))
        row.tap()

        XCTAssertTrue(element(containing: "z5401234").waitForExistence(timeout: 8), "submission PDF header")
        snap("1-submission")

        app.buttons["Comments"].tap()
        XCTAssertTrue(element(containing: "Great, thanks").waitForExistence(timeout: 5))
        let field = app.textViews["Comment"].exists ? app.textViews["Comment"] : app.textFields["Comment"]
        field.tap()
        field.typeText("nice, both base cases are fine")
        app.buttons["Send"].tap()
        XCTAssertTrue(element(containing: "nice, both base cases are fine").waitForExistence(timeout: 5))

        // the same text again is refused as a duplicate
        field.tap()
        field.typeText("nice, both base cases are fine")
        app.buttons["Send"].tap()
        XCTAssertTrue(element(containing: "identical to your last one").waitForExistence(timeout: 5))
        snap("2-comments")

        app.buttons["Set status to Complete"].tap()
        // the refused comment is still in the field, so don't send it with the status
        XCTAssertTrue(app.buttons["Send and set Complete"].waitForExistence(timeout: 5))
        let withComment = app.switches.matching(NSPredicate(format: "label BEGINSWITH %@", "Send your comment too")).firstMatch
        withComment.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        let confirm = app.buttons["Set Complete"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        snap("3-confirm")
        confirm.tap()
        XCTAssertTrue(element(containing: "You set the status to Complete").waitForExistence(timeout: 5))
        XCTAssertTrue(element(containing: "Status Complete").waitForExistence(timeout: 5), "header pill updated")
        snap("4-after-status")
    }

    func testPinAndGrantExtension() throws {
        let row = element(containing: "Lucas Ferreira")
        XCTAssertTrue(row.waitForExistence(timeout: 8))
        row.swipeLeft()
        XCTAssertTrue(app.buttons["Pin"].waitForExistence(timeout: 3))
        app.buttons["Pin"].tap()
        XCTAssertTrue(element(containing: "Pinned").waitForExistence(timeout: 5))

        element(containing: "Lucas Ferreira").tap()
        app.buttons["Comments"].tap()
        let grant = app.buttons["Grant"]
        XCTAssertTrue(grant.waitForExistence(timeout: 5))
        snap("5-extension")
        grant.tap()
        XCTAssertTrue(element(containing: "Granted").waitForExistence(timeout: 5))
    }
}
