//
//  OpenConnectionTests.swift
//  TermoraUITests
//

import TermoraModel
import TermoraVault
import XCTest

/// The Open Connection field (⌘O): find a bookmark, or type an address.
///
/// The hosts end in `.invalid`, a name that never resolves, so no test
/// reaches a real server. A tab appears before the connection fails, and
/// the tab is what these tests look for.
final class OpenConnectionTests: XCTestCase {
    private static let password = "test master password"
    private var documentURL: URL!

    override func setUp() async throws {
        try await super.setUp()
        continueAfterFailure = false

        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("termora-open-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        documentURL = directory.appendingPathComponent("Fixture.termora")

        let prod = Folder(name: "Production")
        _ = try await Vault.create(
            at: documentURL,
            password: Self.password,
            document: Document(
                folders: [prod],
                connections: [
                    Connection(parentID: prod.id, name: "web-01", position: 0, host: "web01.invalid"),
                    Connection(parentID: prod.id, name: "web-02", position: 1, host: "web02.invalid"),
                    Connection(name: "database", host: "db.invalid"),
                ]
            )
        )
    }

    override func tearDown() async throws {
        if let directory = documentURL?.deletingLastPathComponent() {
            try? FileManager.default.removeItem(at: directory)
        }
        try await super.tearDown()
    }

    /// ⌘O reaches the menu from inside a focused pane, and Return opens the
    /// first bookmark that matches.
    func testFindsBookmarkFromAFocusedPane() throws {
        let (app, main) = unlockedWindow()

        // A local shell takes the keyboard first. Ghostty must not eat ⌘O.
        app.typeKey("t", modifierFlags: [.command, .shift])
        XCTAssertTrue(tab("Local", in: main).waitForExistence(timeout: 5))
        sleep(2)

        app.typeKey("o", modifierFlags: [.command])
        let field = main.textFields["open-connection-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5),
                      "⌘O in a focused pane must open the field.")

        field.typeText("data")
        XCTAssertTrue(row("database", in: main).waitForExistence(timeout: 5))
        XCTAssertFalse(row("web-01", in: main).exists,
                       "A bookmark that does not match must not be listed.")

        let shot = XCTAttachment(screenshot: main.screenshot())
        shot.name = "open-connection"
        shot.lifetime = .keepAlways
        add(shot)

        field.typeText("\r")
        XCTAssertTrue(tab("database", in: main).waitForExistence(timeout: 5),
                      "Return must open the first match.")
        XCTAssertFalse(field.exists, "The field must close after it opens a tab.")
    }

    /// The arrow keys choose a row. Return then opens that row, not the first.
    func testArrowChoosesARow() throws {
        let (app, main) = unlockedWindow()

        app.typeKey("o", modifierFlags: [.command])
        let field = main.textFields["open-connection-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText("web")
        XCTAssertTrue(row("web-02", in: main).waitForExistence(timeout: 5))

        app.typeKey(.downArrow, modifierFlags: [])
        field.typeText("\r")
        XCTAssertTrue(tab("web-02", in: main).waitForExistence(timeout: 5),
                      "↓ then Return must open the second match.")
        XCTAssertFalse(tab("web-01", in: main).exists)
    }

    /// An address with a user name opens a quick connection, with no
    /// bookmark, and the tab offers to save it.
    func testTypedAddressOpensQuickConnection() throws {
        let (app, main) = unlockedWindow()

        app.typeKey("o", modifierFlags: [.command])
        let field = main.textFields["open-connection-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        // No port: the test runner drops a typed `:` with some keyboard
        // layouts. `OpenConnectionTests` in TermoraModel covers the port.
        field.typeText("deploy@web01.invalid")
        XCTAssertTrue(main.descendants(matching: .any)
            .matching(identifier: "open-connection-row-quick").firstMatch
            .waitForExistence(timeout: 5))

        field.typeText("\r")
        let quickTab = tab("deploy@web01.invalid", in: main)
        XCTAssertTrue(quickTab.waitForExistence(timeout: 5),
                      "Return must open a tab named after the address.")

        // XCUITest finds no hit point inside the title bar tab strip, so the
        // click goes to the middle of the tab name by its coordinates.
        main.staticTexts.matching(identifier: "tab-deploy@web01.invalid").firstMatch
            .coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .rightClick()
        let save = app.menuItems["Save as Bookmark"]
        XCTAssertTrue(save.waitForExistence(timeout: 5),
                      "A quick tab must offer to save itself as a bookmark.")
        save.click()

        // The editor opens on the new bookmark. Close it and look at the tree.
        let done = app.buttons["Done"]
        XCTAssertTrue(done.waitForExistence(timeout: 5), "Saving must open the editor.")
        done.click()
        XCTAssertTrue(main.staticTexts["deploy@web01.invalid"].waitForExistence(timeout: 5),
                      "The bookmark must appear in the sidebar.")
    }

    /// Escape closes the field and opens nothing.
    func testEscapeCloses() throws {
        let (app, main) = unlockedWindow()

        app.typeKey("o", modifierFlags: [.command])
        let field = main.textFields["open-connection-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText("web")
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(waitUntil { !field.exists }, "Escape must close the field.")
        XCTAssertFalse(tab("web-01", in: main).exists, "Escape must open nothing.")
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
        XCTAssertTrue(window.staticTexts["database"].waitForExistence(timeout: 10))
        return (app, window)
    }

    private func tab(_ name: String, in main: XCUIElement) -> XCUIElement {
        main.descendants(matching: .any).matching(identifier: "tab-\(name)").firstMatch
    }

    private func row(_ name: String, in main: XCUIElement) -> XCUIElement {
        main.descendants(matching: .any).matching(identifier: "open-connection-row-\(name)").firstMatch
    }

    private func waitUntil(_ condition: @escaping () -> Bool) -> Bool {
        let predicate = NSPredicate { _, _ in condition() }
        let reached = expectation(for: predicate, evaluatedWith: nil)
        return XCTWaiter.wait(for: [reached], timeout: 5) == .completed
    }
}
