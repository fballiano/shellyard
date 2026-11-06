//
//  ReconnectTests.swift
//  TermoraUITests
//

import TermoraModel
import TermoraVault
import XCTest

/// A connection that the server drops: the tab keeps its panes under a bar,
/// and Reconnect (⌘R) brings it back.
///
/// The bookmark's "After connecting" text drops the connection from the far
/// side, three seconds after the first connect only: it kills the
/// `sshd-session` process that serves the login shell. A marker file stops it
/// from doing so again after the reconnect. The text is pasted, so no
/// keyboard layout can change it, and it runs through `sh`, so your login
/// shell does not matter.
///
/// The OpenSSH server runs outside the test runner. Run it with:
///
///   ./Scripts/uitest-ssh.sh TermoraUITests/ReconnectTests
final class ReconnectTests: XCTestCase {
    private static let password = "test master password"

    private var documentURL: URL!
    private var homeURL: URL!

    override func setUp() async throws {
        try await super.setUp()
        continueAfterFailure = false

        let environment = ProcessInfo.processInfo.environment
        guard let portText = environment["TERMORA_TEST_SSH_PORT"],
              let port = Int(portText),
              let keyPath = environment["TERMORA_TEST_SSH_KEY"]
        else {
            throw XCTSkip("No local sshd. Run this through Scripts/uitest-ssh.sh.")
        }

        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("termora-uitest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        documentURL = directory.appendingPathComponent("Fixture.termora")
        homeURL = directory.appendingPathComponent("home")
        try FileManager.default.createDirectory(
            at: homeURL.appendingPathComponent(".ssh"),
            withIntermediateDirectories: true
        )

        let marker = directory.appendingPathComponent("dropped").path
        // The delay lets a slow login shell start: fish drops what arrives
        // while it starts up.
        let drop = "{DELAY:2500}sh -c 'test -e \"\(marker)\" || (touch \"\(marker)\"; sleep 3; "
            + "kill -9 $(ps -o ppid= -p $PPID))'{ENTER}"
        let settings = NodeSettings(
            username: .value(NSUserName()),
            authentication: .value(.privateKey(path: keyPath, passphrase: Secret(""))),
            hostKeyPolicy: .value(.acceptNew),
            afterConnectText: .value(drop)
        )
        let gamma = Connection(name: "gamma", host: "127.0.0.1", port: port, settings: settings)
        _ = try await Vault.create(
            at: documentURL, password: Self.password,
            document: Document(folders: [], connections: [gamma])
        )
    }

    override func tearDown() async throws {
        if let directory = documentURL?.deletingLastPathComponent() {
            try? FileManager.default.removeItem(at: directory)
        }
        try await super.tearDown()
    }

    func testDroppedConnectionKeepsPanesAndReconnects() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-TermoraLastDocumentPath", documentURL.path]
        app.launchEnvironment["HOME"] = homeURL.path
        app.launch()
        let main = app.windows.firstMatch
        XCTAssertTrue(main.waitForExistence(timeout: 20))

        let field = main.secureTextFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.click()
        field.typeText("\(Self.password)\r")
        XCTAssertTrue(main.staticTexts["gamma"].firstMatch.waitForExistence(timeout: 10))

        main.staticTexts["gamma"].firstMatch.doubleClick()
        let tab = main.descendants(matching: .any).matching(identifier: "tab-gamma").firstMatch
        XCTAssertTrue(tab.waitForExistence(timeout: 10))

        // A split before the drop, so the reconnect must rebuild two panes.
        sleep(2)
        app.typeKey("d", modifierFlags: [.command])

        let bar = main.descendants(matching: .any)
            .matching(identifier: "lost-connection-bar").firstMatch
        XCTAssertTrue(bar.waitForExistence(timeout: 20),
                      "A connection that the server drops must show the bar.")
        attachScreenshot(of: main, named: "lost")

        // Ghostty asks to close a finished pane on any key. The pane must
        // stay, so its last output can still be read.
        app.typeKey("x", modifierFlags: [])
        sleep(1)
        XCTAssertTrue(tab.exists, "A key in a lost pane must not close the tab.")
        XCTAssertTrue(bar.exists, "The bar must stay until you choose.")

        app.typeKey("r", modifierFlags: [.command])
        XCTAssertTrue(waitUntil(timeout: 20) { !bar.exists },
                      "⌘R must reconnect, and the bar must go.")
        XCTAssertTrue(tab.exists)
        sleep(2)
        attachScreenshot(of: main, named: "reconnected")
    }

    // MARK: - Helpers

    private func attachScreenshot(of element: XCUIElement, named name: String) {
        let shot = XCTAttachment(screenshot: element.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    private func waitUntil(timeout: TimeInterval, _ condition: @escaping () -> Bool) -> Bool {
        let predicate = NSPredicate { _, _ in condition() }
        let reached = expectation(for: predicate, evaluatedWith: nil)
        return XCTWaiter.wait(for: [reached], timeout: timeout) == .completed
    }
}
