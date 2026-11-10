//
//  ConnectionsTransferTests.swift
//  ShellyardUITests
//

import ShellyardModel
import ShellyardVault
import XCTest

/// Opens the export and import sheets through the real menus.
///
/// The file panels belong to macOS, so the test stops before them. The JSON
/// format, the inherited settings, and the import plan are covered by the
/// ShellyardModel tests.
final class ConnectionsTransferTests: XCTestCase {
    private static let password = "test master password"
    private var documentURL: URL!

    override func setUp() async throws {
        try await super.setUp()
        continueAfterFailure = false

        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("shellyard-transfer-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        documentURL = directory.appendingPathComponent("Fixture.shellyard")

        let folder = Folder(name: "Prod", settings: NodeSettings(username: .value("root")))
        let document = ShellyardModel.Document(
            folders: [folder],
            connections: [
                Connection(parentID: folder.id, name: "web-01", host: "web01.example.com"),
                Connection(parentID: folder.id, name: "web-02", position: 1, host: "web02.example.com"),
            ]
        )
        _ = try await Vault.create(at: documentURL, password: Self.password, document: document)
    }

    override func tearDown() async throws {
        if let directory = documentURL?.deletingLastPathComponent() {
            try? FileManager.default.removeItem(at: directory)
        }
        try await super.tearDown()
    }

    private func launchAndUnlock() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ShellyardLastDocumentPath", documentURL.path]
        app.launch()

        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 20))
        let field = window.secureTextFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.click()
        field.typeText("\(Self.password)\r")
        return app
    }

    private func text(_ fragment: String, in element: XCUIElement) -> XCUIElement {
        element.staticTexts.matching(NSPredicate(format: "value CONTAINS[c] %@", fragment)).firstMatch
    }

    func testExportSheetWarnsBeforeItWritesPasswords() throws {
        let app = launchAndUnlock()

        let fileMenu = app.menuBars.menuBarItems["File"]
        XCTAssertTrue(fileMenu.waitForExistence(timeout: 10))
        fileMenu.click()
        let exportItem = fileMenu.menuItems["Export All Connections…"]
        XCTAssertTrue(exportItem.waitForExistence(timeout: 5))
        exportItem.click()

        let sheet = app.sheets.firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 10), "The export sheet must appear.")
        XCTAssertTrue(text("1 folder and 2 connections", in: sheet).exists,
                      "The sheet must say what goes into the file.")

        // The passwords stay out until the person asks for them, and the
        // warning appears only then.
        let toggle = sheet.checkBoxes["includeSecrets"]
        XCTAssertTrue(toggle.exists)
        XCTAssertEqual(toggle.value as? Int, 0, "Passwords must be left out by default.")
        XCTAssertFalse(text("plain text", in: sheet).exists)
        toggle.click()
        XCTAssertTrue(text("plain text", in: sheet).waitForExistence(timeout: 5),
                      "The sheet must warn that the passwords are readable in the file.")

        XCTAssertTrue(sheet.buttons["Export…"].isEnabled)
        sheet.buttons["Cancel"].click()
    }

    func testFolderExportExplainsInheritedSettings() throws {
        let app = launchAndUnlock()

        let row = app.windows.firstMatch.staticTexts["Prod"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.rightClick()
        let exportItem = app.menuItems["Export…"]
        XCTAssertTrue(exportItem.waitForExistence(timeout: 5),
                      "The folder menu must offer the export.")
        exportItem.click()

        let sheet = app.sheets.firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 10))
        XCTAssertTrue(text("Export the Folder “Prod”", in: sheet).exists,
                      "The title must name the folder.")
        XCTAssertTrue(text("1 folder and 2 connections", in: sheet).exists,
                      "A folder goes out with everything inside it.")
        sheet.buttons["Cancel"].click()
    }

    func testImportSheetWaitsForAFile() throws {
        let app = launchAndUnlock()

        let fileMenu = app.menuBars.menuBarItems["File"]
        XCTAssertTrue(fileMenu.waitForExistence(timeout: 10))
        fileMenu.click()
        let importItem = fileMenu.menuItems["Import Connections…"]
        XCTAssertTrue(importItem.waitForExistence(timeout: 5))
        XCTAssertTrue(importItem.isEnabled)
        importItem.click()

        let sheet = app.sheets.firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 10), "The import sheet must appear.")
        XCTAssertTrue(text("Nothing already in it is removed", in: sheet).exists)
        XCTAssertTrue(text("No file chosen", in: sheet).exists)
        XCTAssertFalse(sheet.buttons["Import"].isEnabled,
                       "Import must wait until a file is chosen.")
        sheet.buttons["Cancel"].click()
    }
}
