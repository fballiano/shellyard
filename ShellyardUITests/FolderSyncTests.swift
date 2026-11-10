//
//  FolderSyncTests.swift
//  ShellyardUITests
//

import ShellyardModel
import ShellyardVault
import XCTest

/// Syncs a folder from the HTTP server of `Scripts/uitest-sync.sh`.
///
/// The merge rules are covered by the ShellyardModel tests. This test proves
/// the parts that only the real app has: the request, HTTP Basic, the menu
/// item, and the sidebar. The server answers 401 without the right
/// credentials, so entries in the sidebar prove that the credentials arrived.
final class FolderSyncTests: XCTestCase {
    private static let password = "test master password"
    private var documentURL: URL!

    override func setUp() async throws {
        try await super.setUp()
        continueAfterFailure = false

        guard let port = ProcessInfo.processInfo.environment["SHELLYARD_TEST_SYNC_PORT"] else {
            throw XCTSkip("No local list server. Run this through Scripts/uitest-sync.sh.")
        }

        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("shellyard-sync-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        documentURL = directory.appendingPathComponent("Fixture.shellyard")

        // Manual, so the sync starts from the menu and not by itself.
        let fleet = Folder(name: "Fleet", sync: FolderSync(
            url: "http://127.0.0.1:\(port)/list.json",
            username: "inventory",
            password: Secret("s3cret"),
            interval: .manual
        ))
        let document = ShellyardModel.Document(folders: [fleet])
        _ = try await Vault.create(at: documentURL, password: Self.password, document: document)
    }

    override func tearDown() async throws {
        if let directory = documentURL?.deletingLastPathComponent() {
            try? FileManager.default.removeItem(at: directory)
        }
        try await super.tearDown()
    }

    func testSyncNowFillsTheFolder() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ShellyardLastDocumentPath", documentURL.path]
        app.launch()

        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 20))
        let field = window.secureTextFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.click()
        field.typeText("\(Self.password)\r")

        let fleet = window.staticTexts["Fleet"]
        XCTAssertTrue(fleet.waitForExistence(timeout: 10))
        XCTAssertFalse(window.staticTexts["synced-web-1"].exists,
                       "A manual folder must not sync by itself.")

        fleet.rightClick()
        let syncItem = app.menuItems["Sync Now"]
        XCTAssertTrue(syncItem.waitForExistence(timeout: 5),
                      "A synced folder must offer Sync Now.")
        syncItem.click()

        XCTAssertTrue(window.staticTexts["synced-web-1"].waitForExistence(timeout: 15),
                      "The sync must add the connections of the list.")
        XCTAssertTrue(window.staticTexts["synced-databases"].exists)
        XCTAssertTrue(window.staticTexts["synced-db-1"].exists)
    }
}
