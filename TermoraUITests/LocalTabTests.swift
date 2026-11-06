//
//  LocalTabTests.swift
//  TermoraUITests
//

import TermoraModel
import TermoraVault
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
            .appendingPathComponent("termora-local-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        documentURL = directory.appendingPathComponent("Fixture.termora")

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

    // MARK: - Helpers

    private func unlockedWindow() -> (XCUIApplication, XCUIElement) {
        let app = XCUIApplication()
        app.launchArguments = ["-TermoraLastDocumentPath", documentURL.path]
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

    private func waitUntil(_ condition: @escaping () -> Bool) -> Bool {
        let predicate = NSPredicate { _, _ in condition() }
        let reached = expectation(for: predicate, evaluatedWith: nil)
        return XCTWaiter.wait(for: [reached], timeout: 5) == .completed
    }
}
