//
//  LocalTabTests.swift
//  ShellyardUITests
//

import ShellyardModel
import ShellyardVault
import XCTest

/// Local tabs: a login shell on this Mac, with no connection.
///
/// These tests need no SSH server. ⌘T on a connection tab is checked in
/// `TabShortcutsTests`, which has one.
final class LocalTabTests: XCTestCase {
    private static let password = "test master password"
    private var documentURL: URL!

    override func setUp() async throws {
        try await super.setUp()
        continueAfterFailure = false

        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("shellyard-local-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        documentURL = directory.appendingPathComponent("Fixture.shellyard")

        let connection = Connection(name: "web-01", host: "web01.example.com")
        _ = try await Vault.create(
            at: documentURL,
            password: Self.password,
            document: Document(connections: [connection])
        )
    }

    override func tearDown() async throws {
        if let directory = documentURL?.deletingLastPathComponent() {
            try? FileManager.default.removeItem(at: directory)
        }
        try await super.tearDown()
    }

    /// The row sits above the filter, because the filter finds bookmarks
    /// only. One click on it opens a local tab.
    func testSidebarRowOpensLocalTab() throws {
        let (app, main) = unlockedWindow()

        let row = main.descendants(matching: .any).matching(identifier: "local-shell").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), "The sidebar must offer a local shell.")
        let filter = main.textFields["sidebar-filter"]
        XCTAssertTrue(filter.exists, "The sidebar must still have its filter.")
        XCTAssertLessThan(row.frame.midY, filter.frame.midY,
                          "The local shell row must sit above the filter.")

        let shot = XCTAttachment(screenshot: main.screenshot())
        shot.name = "sidebar"
        shot.lifetime = .keepAlways
        add(shot)

        // The filter still filters.
        filter.click()
        filter.typeText("zzz")
        XCTAssertTrue(waitUntil { !main.staticTexts["web-01"].exists },
                      "The filter must hide a bookmark that does not match.")
        XCTAssertTrue(row.exists, "The filter must not hide the local shell row.")
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(main.staticTexts["web-01"].waitForExistence(timeout: 5),
                      "Escape must empty the filter.")

        row.click()
        XCTAssertTrue(localTabs(in: main).firstMatch.waitForExistence(timeout: 5),
                      "A click on the row must open a local tab.")
    }

    /// ⌘T with no tab opens a local tab. ⌘T on a local tab opens one more.
    func testCommandTOpensLocalTabs() throws {
        let (app, main) = unlockedWindow()

        app.typeKey("t", modifierFlags: [.command])
        XCTAssertTrue(localTabs(in: main).firstMatch.waitForExistence(timeout: 5),
                      "⌘T with no tab must open a local tab.")
        // Give the shell time to take the keyboard: the pane must pass ⌘T on
        // to the menu, not eat it.
        sleep(2)

        let before = localTabs(in: main).count
        app.typeKey("t", modifierFlags: [.command])
        XCTAssertTrue(waitUntil { self.localTabs(in: main).count > before },
                      "⌘T on a local tab must open a second local tab.")
    }

    /// ⌃⌘L closes every session, as the README promises. After the unlock,
    /// no tab from before the lock is left.
    func testLockClosesEverySession() throws {
        let (app, main) = unlockedWindow()

        app.typeKey("t", modifierFlags: [.command, .shift])
        XCTAssertTrue(localTabs(in: main).firstMatch.waitForExistence(timeout: 5))
        sleep(1)

        app.typeKey("l", modifierFlags: [.command, .control])
        let field = main.secureTextFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10), "⌃⌘L must lock the document.")
        field.click()
        field.typeText("\(Self.password)\r")
        XCTAssertTrue(main.staticTexts["web-01"].waitForExistence(timeout: 10))

        XCTAssertFalse(localTabs(in: main).firstMatch.exists,
                       "A lock must close every session, local shells too.")
    }

    /// A split must not restart the pane it splits, and closing one pane
    /// must not restart the other.
    ///
    /// The surface, and so the process, belongs to the pane's platform view.
    /// A split moves the pane to a new place in the view tree; a new view
    /// there once started a new shell and ended the running program. The
    /// test sees the program through Shellyard itself: ⌘W on a pane with a
    /// running program asks first, and a fresh idle shell closes at once.
    func testSplitKeepsTheRunningProgram() throws {
        let (app, main) = unlockedWindow()

        app.typeKey("t", modifierFlags: [.command, .shift])
        XCTAssertTrue(localTabs(in: main).firstMatch.waitForExistence(timeout: 5))
        sleep(3)
        app.typeText("sleep 120\r")
        sleep(1)

        app.typeKey("d", modifierFlags: [.command])
        sleep(2)
        let question = app.staticTexts["A program still runs in it."]

        // The left pane, which ran the program before the split.
        main.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.5)).click()
        app.typeKey("w", modifierFlags: [.command])
        XCTAssertTrue(question.waitForExistence(timeout: 5),
                      "The split restarted the pane: its program is gone.")
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(waitUntil { !question.exists })

        // Close the right pane, an idle shell. The left pane moves up.
        main.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5)).click()
        app.typeKey("w", modifierFlags: [.command])
        sleep(2)
        if question.exists { app.typeKey(.return, modifierFlags: []) }
        sleep(1)

        main.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
        app.typeKey("w", modifierFlags: [.command])
        XCTAssertTrue(question.waitForExistence(timeout: 5),
                      "Closing the other pane restarted this one: its program is gone.")
        app.typeKey(.escape, modifierFlags: [])
    }

    /// A bell in a hidden tab marks that tab. Choosing the tab removes
    /// the mark.
    func testBellMarksHiddenTab() throws {
        let (app, main) = unlockedWindow()

        app.typeKey("t", modifierFlags: [.command, .shift])
        XCTAssertTrue(localTabs(in: main).firstMatch.waitForExistence(timeout: 5))
        sleep(3)
        app.typeText("sleep 2; printf '\\a'\r")
        app.typeKey("t", modifierFlags: [.command, .shift])

        let first = localTabs(in: main).element(boundBy: 0)
        XCTAssertTrue(waitUntil(timeout: 10) { first.value as? String == "Needs attention" },
                      "The bell did not mark the hidden tab.")

        app.typeKey("1", modifierFlags: [.command])
        XCTAssertTrue(waitUntil { (first.value as? String ?? "").isEmpty },
                      "The mark stayed on the tab in view.")
    }

    /// A long command that fails in a hidden tab marks that tab red. This
    /// needs a shell with shell integration (OSC 133), as the local
    /// shell has.
    func testFailedLongCommandMarksHiddenTab() throws {
        let (app, main) = unlockedWindow()

        app.typeKey("t", modifierFlags: [.command, .shift])
        XCTAssertTrue(localTabs(in: main).firstMatch.waitForExistence(timeout: 5))
        sleep(3)
        app.typeText("sleep 6; false\r")
        app.typeKey("t", modifierFlags: [.command, .shift])

        let first = localTabs(in: main).element(boundBy: 0)
        XCTAssertTrue(waitUntil(timeout: 15) { first.value as? String == "Command failed" },
                      "The failed command did not mark the hidden tab.")
    }

    // MARK: - Helpers

    private func unlockedWindow() -> (XCUIApplication, XCUIElement) {
        let app = XCUIApplication()
        app.launchArguments = ["-ShellyardLastDocumentPath", documentURL.path]
        app.launch()

        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 20))
        let field = window.secureTextFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.click()
        field.typeText("\(Self.password)\r")
        XCTAssertTrue(window.staticTexts["web-01"].waitForExistence(timeout: 10))
        return (app, window)
    }

    private func localTabs(in main: XCUIElement) -> XCUIElementQuery {
        main.descendants(matching: .any).matching(identifier: "tab-Local")
    }

    private func waitUntil(
        timeout: TimeInterval = 5, _ condition: @escaping () -> Bool
    ) -> Bool {
        let predicate = NSPredicate { _, _ in condition() }
        let reached = expectation(for: predicate, evaluatedWith: nil)
        return XCTWaiter.wait(for: [reached], timeout: timeout) == .completed
    }
}
