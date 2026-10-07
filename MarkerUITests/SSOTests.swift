import XCTest

/// Checks the Microsoft sign-in page loads in the sheet. Types nothing.
@MainActor
final class SSOTests: XCTestCase {
    func testMicrosoftPageLoadsInSheet() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "NO"]
        app.launch()
        let signIn = app.buttons["Sign in with UNSW"]
        guard signIn.waitForExistence(timeout: 10) else { throw XCTSkip("already signed in on this simulator") }
        signIn.tap()
        XCTAssertTrue(app.webViews.firstMatch.waitForExistence(timeout: 20), "web view sheet opens")
        let msPage = app.webViews.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS[c] 'sign in' OR label CONTAINS[c] 'zID' OR label CONTAINS[c] 'email'")).firstMatch
        XCTAssertTrue(msPage.waitForExistence(timeout: 30), "Microsoft's sign-in form rendered")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'microsoftonline'")).firstMatch.exists
                      || app.buttons.matching(NSPredicate(format: "label CONTAINS 'microsoftonline'")).firstMatch.exists,
                      "host label shows Microsoft's domain")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "S1-microsoft"
        shot.lifetime = .keepAlways
        add(shot)
        app.buttons["Cancel"].tap()
        XCTAssertTrue(signIn.waitForExistence(timeout: 5), "cancel returns to sign-in")
    }
}
