import XCTest

/// Drives demo mode for the walkthrough video. TEST_RUNNER_VIDEO_DURATIONS gives each clip's length.
@MainActor
final class DemoVideoTests: XCTestCase {
    var app: XCUIApplication!
    var durations: [String: Double] = [:]

    override func setUp() async throws {
        guard let raw = ProcessInfo.processInfo.environment["VIDEO_DURATIONS"] else { throw XCTSkip("only for recording the demo video") }
        for pair in raw.split(separator: ",") {
            let kv = pair.split(separator: "=")
            if kv.count == 2, let d = Double(kv[1]) { durations[String(kv[0])] = d }
        }
        continueAfterFailure = true
        app = XCUIApplication()
        app.launchArguments = ["-demo", "NO"]
        app.launch()
    }

    private func pause(_ s: Double) { Thread.sleep(forTimeInterval: s) }

    private func element(containing text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    private func step(_ id: String, _ actions: () -> Void) {
        let start = Date()
        print("VIDEO-STEP \(id) \(String(format: "%.3f", start.timeIntervalSince1970))")
        actions()
        let remaining = (durations[id] ?? 5) + 0.8 - Date().timeIntervalSince(start)
        if remaining > 0 { pause(remaining) }
    }

    func testRecordWalkthrough() {
        XCTAssertTrue(app.buttons["Sign in with UNSW"].waitForExistence(timeout: 20))
        pause(1.5)

        step("s01") {
            pause((durations["s01"] ?? 13) - 3.5)
            app.buttons["Try the demo"].tap()
        }
        step("s02") {
            _ = element(containing: "Priya Raman").waitForExistence(timeout: 10)
            pause(7)
            app.buttons["Waiting 2d+"].firstMatch.tap()
            pause(4.5)
            app.buttons["Waiting 2d+"].firstMatch.tap()
        }
        step("s03") {
            element(containing: "Priya Raman").tap()
            _ = element(containing: "Page 1 of").waitForExistence(timeout: 10)
            pause(3.5)
            app.swipeUp(velocity: .slow)
        }
        step("s04") {
            app.buttons["Files"].tap()
            pause(1.8)
            element(containing: "main.tex").tap()
            pause(3.2)
            app.navigationBars.buttons.element(boundBy: 0).tap()
        }
        step("s05") {
            app.buttons["Sheet"].tap()
        }
        step("s06") {
            app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Comments")).firstMatch.tap()
            pause(3)
            let field = app.textViews["Comment"].exists ? app.textViews["Comment"] : app.textFields["Comment"]
            field.tap()
            field.typeText("nice work, both base cases are fine")
            pause(0.4)
            app.buttons["Send"].tap()
        }
        step("s07") {
            pause(1.2)
            app.buttons["Set status to Complete"].tap()
            pause(3)
            app.buttons["Set Complete"].tap()
        }
        step("s08") {
            app.navigationBars.buttons.element(boundBy: 0).tap()
            pause(0.8)
            app.tabBars.buttons["Notifications"].tap()
            pause(5.5)
            app.swipeUp(velocity: .slow)
        }
        step("s09") {
            app.tabBars.buttons["Students"].tap()
            pause(2.2)
            app.cells.element(boundBy: 1).tap()
        }
        step("s10") {
            app.tabBars.buttons["Settings"].tap()
            pause(2.2)
            app.swipeUp(velocity: .slow)
        }
        pause(1.5)
    }
}
