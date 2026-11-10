import Foundation
import Testing
@testable import ShellyardModel

/// A small document:
///   Prod                username = "root", password "s3cret", jump host
///     └── Web           colour = .blue
///           ├── web-01  port 2222, a tunnel, a command before connect
///           └── web-02  username = "deploy"
///   lab                 a connection at the top level
private struct Fixture {
    let prod = Folder(name: "Prod", position: 0, settings: NodeSettings(
        username: .value("root"),
        authentication: .value(.password(Secret("s3cret"))),
        jumpHost: .value("bastion.example.com")
    ))
    var web: Folder
    var webOne: Connection
    var webTwo: Connection
    let lab = Connection(name: "lab", position: 1, host: "lab.local", isFavorite: true)

    init() {
        web = Folder(parentID: prod.id, name: "Web", settings: NodeSettings(colorTag: .value(.blue)))
        webOne = Connection(
            parentID: web.id, name: "web-01", position: 0, host: "10.0.1.11", port: 2222,
            settings: NodeSettings(beforeConnect: .value(LocalCommand(
                name: "Open firewall", launchPath: "/usr/local/bin/knock", arguments: "$HOST$"
            ))),
            forwards: [PortForward(kind: .local, listenPort: 8080,
                                   destinationHost: "localhost", destinationPort: 80)],
            notes: "Front end"
        )
        webTwo = Connection(parentID: web.id, name: "web-02", position: 1, host: "10.0.1.12",
                            settings: NodeSettings(username: .value("deploy")))
    }

    var document: Document {
        Document(folders: [prod, web], connections: [webOne, webTwo, lab])
    }

    var index: DocumentIndex { DocumentIndex(document) }
}

private func json(_ text: String) -> Data { Data(text.utf8) }

private func names(_ items: [ConnectionsFile.Item]) -> [String] {
    items.map { item in
        switch item {
        case let .folder(folder, _, _): folder.name
        case let .connection(connection, _): connection.name
        case let .invalid(name, _): "invalid:\(name ?? "?")"
        }
    }
}

// MARK: - Round trip

@Test("The whole document survives an export and an import")
func wholeDocumentRoundTrip() throws {
    let fixture = Fixture()
    let file = ConnectionsFile(exporting: nil, from: fixture.index, includeSecrets: true)
    let read = try ConnectionsFile.decode(file.encoded())
    #expect(names(read.items) == ["Prod", "lab"])

    let plan = ConnectionsImport(file: read, under: nil, firstPosition: 0, keepCommands: true)
    let imported = DocumentIndex(Document(folders: plan.folders, connections: plan.connections))
    let webOne = try #require(plan.connections.first { $0.name == "web-01" })

    #expect(plan.folders.count == 2)
    #expect(plan.connections.count == 3)
    #expect(webOne.id != fixture.webOne.id)
    #expect(webOne.port == 2222)
    #expect(webOne.notes == "Front end")
    #expect(webOne.forwards.first?.destinationPort == 80)
    #expect(webOne.forwards.first?.id != fixture.webOne.forwards.first?.id)
    #expect(webOne.settings.beforeConnect.ownValue?.launchPath == "/usr/local/bin/knock")

    let settings = imported.effectiveSettings(for: webOne)
    #expect(settings.username == "root")
    #expect(settings.authentication == .password(Secret("s3cret")))
    #expect(settings.jumpHost == "bastion.example.com")
    #expect(settings.colorTag == .blue)
    #expect(plan.connections.first { $0.name == "lab" }?.isFavorite == true)
    #expect(plan.connections.first { $0.name == "lab" }?.port == nil)
}

@Test("The import keeps the order of the file")
func importKeepsOrder() throws {
    let fixture = Fixture()
    let file = ConnectionsFile(exporting: nil, from: fixture.index, includeSecrets: false)
    let plan = ConnectionsImport(file: file, under: nil, firstPosition: 5, keepCommands: false)
    let index = DocumentIndex(Document(folders: plan.folders, connections: plan.connections))
    #expect(index.children(of: nil).map(\.name) == ["Prod", "lab"])
    #expect(index.children(of: nil).map(\.position) == [5, 6])
    let web = try #require(plan.folders.first { $0.name == "Web" })
    #expect(index.children(of: web.id).map(\.name) == ["web-01", "web-02"])
}

// MARK: - Branches and secrets

@Test("A branch takes the values it inherits from the folders above it")
func branchBakesInheritedValues() throws {
    let fixture = Fixture()
    let file = ConnectionsFile(exporting: fixture.web.id, from: fixture.index, includeSecrets: true)
    #expect(names(file.items) == ["Web"])
    guard case let .folder(web, _, children) = try #require(file.items.first) else {
        Issue.record("The branch must start with the folder")
        return
    }
    #expect(web.settings.username == .value("root"))
    #expect(web.settings.jumpHost == .value("bastion.example.com"))
    #expect(web.settings.colorTag == .value(.blue))
    // Nothing above sets these, so they still inherit on the other Mac.
    #expect(web.settings.compression == .inherit)
    #expect(names(children) == ["web-01", "web-02"])
}

@Test("One connection takes the values it inherits")
func singleConnectionBakesInheritedValues() throws {
    let fixture = Fixture()
    let file = ConnectionsFile(exporting: fixture.webTwo.id, from: fixture.index, includeSecrets: true)
    guard case let .connection(connection, externalID) = try #require(file.items.first) else {
        Issue.record("The export must hold the connection")
        return
    }
    #expect(file.items.count == 1)
    #expect(externalID == fixture.webTwo.id.uuidString)
    #expect(connection.settings.username == .value("deploy"))
    #expect(connection.settings.authentication == .value(.password(Secret("s3cret"))))
    #expect(connection.settings.colorTag == .value(.blue))
}

@Test("An export without secrets keeps the method and drops the password")
func exportWithoutSecrets() throws {
    let fixture = Fixture()
    let file = ConnectionsFile(exporting: fixture.webTwo.id, from: fixture.index, includeSecrets: false)
    let data = try file.encoded()
    let text = String(decoding: data, as: UTF8.self)
    #expect(!text.contains("s3cret"))
    #expect(text.contains("\"method\" : \"password\""))

    let plan = ConnectionsImport(
        file: try ConnectionsFile.decode(data), under: nil, firstPosition: 0, keepCommands: false
    )
    #expect(plan.missingSecrets.map(\.path) == ["web-02"])
}

@Test("A private key keeps its path when the passphrase is dropped")
func privateKeyWithoutPassphrase() throws {
    let connection = Connection(name: "k", host: "h", settings: NodeSettings(
        authentication: .value(.privateKey(path: "~/.ssh/id_ed25519", passphrase: Secret("pp")))
    ))
    let index = DocumentIndex(Document(connections: [connection]))
    let text = String(decoding: try ConnectionsFile(
        exporting: nil, from: index, includeSecrets: false
    ).encoded(), as: UTF8.self)
    #expect(text.contains("~/.ssh/id_ed25519"))
    #expect(!text.contains("\"pp\""))
}

// MARK: - Reading what a person or a script wrote

@Test("A hand-written file reads, and a missing setting inherits")
func handWrittenFile() throws {
    let file = try ConnectionsFile.decode(json("""
    {
      "format": "shellyard.connections",
      "version": 1,
      "items": [
        {
          "type": "folder", "id": "prod", "name": "Production",
          "settings": {
            "username": "deploy",
            "authentication": { "method": "privateKey", "path": "~/.ssh/id_ed25519" },
            "colorTag": "red",
            "hostKeyPolicy": "acceptNew",
            "jumpHost": null
          },
          "items": [
            { "type": "connection", "id": "web-1", "name": "web-1", "host": "10.0.1.11",
              "forwards": [ { "kind": "dynamic", "listenPort": 1080 } ],
              "someFutureField": true }
          ]
        }
      ]
    }
    """))
    guard case let .folder(folder, externalID, children) = try #require(file.items.first),
          case let .connection(connection, childID) = try #require(children.first) else {
        Issue.record("The tree must read as a folder with one connection")
        return
    }
    #expect(externalID == "prod")
    #expect(childID == "web-1")
    #expect(folder.settings.username == .value("deploy"))
    #expect(folder.settings.authentication == .value(.privateKey(path: "~/.ssh/id_ed25519",
                                                                   passphrase: .empty)))
    #expect(folder.settings.colorTag == .value(.red))
    #expect(folder.settings.hostKeyPolicy == .value(.acceptNew))
    #expect(folder.settings.jumpHost == .inherit)
    #expect(connection.settings == .inheritAll)
    #expect(connection.port == nil)
    #expect(connection.forwards.first?.kind == .dynamic)
    #expect(connection.forwards.first?.isEnabled == true)
}

@Test("A bad entry is reported, and the entries around it still come through")
func badEntryDoesNotStopTheRead() throws {
    let file = try ConnectionsFile.decode(json("""
    {
      "format": "shellyard.connections",
      "version": 1,
      "items": [
        { "type": "connection", "name": "good-1", "host": "a" },
        { "type": "connection", "name": "no-host" },
        { "type": "connection", "name": "bad-port", "host": "b", "port": 70000 },
        { "type": "connection", "name": "bad-colour", "host": "c", "settings": { "colorTag": "pink" } },
        { "type": "connection", "name": "bad-method", "host": "d",
          "settings": { "authentication": { "method": "telepathy" } } },
        { "type": "printer", "name": "odd" },
        42,
        { "type": "connection", "name": "good-2", "host": "e" }
      ]
    }
    """))
    #expect(names(file.items) == [
        "good-1", "invalid:no-host", "invalid:bad-port", "invalid:bad-colour",
        "invalid:bad-method", "invalid:odd", "invalid:?", "good-2",
    ])

    let plan = ConnectionsImport(file: file, under: nil, firstPosition: 0, keepCommands: false)
    #expect(plan.connections.map(\.name) == ["good-1", "good-2"])
    #expect(plan.connections.map(\.position) == [0, 1])
    #expect(plan.problems.count == 6)
    #expect(plan.problems.first?.text.contains("host") == true)
}

@Test("A file that is not a connections file is refused")
func wrongFormatIsRefused() {
    #expect(throws: ConnectionsFileError.notAConnectionsFile) {
        try ConnectionsFile.decode(json("{\"format\": \"something.else\", \"version\": 1}"))
    }
    #expect(throws: ConnectionsFileError.notAConnectionsFile) {
        try ConnectionsFile.decode(json("not json"))
    }
}

@Test("A file from a newer version is refused with the version")
func newerVersionIsRefused() {
    #expect(throws: ConnectionsFileError.newerVersion(2)) {
        try ConnectionsFile.decode(json("{\"format\": \"shellyard.connections\", \"version\": 2}"))
    }
}

// MARK: - Commands that run on this Mac

@Test("A command before connect stays only when the person allows it")
func commandsNeedPermission() throws {
    let fixture = Fixture()
    let file = ConnectionsFile(exporting: fixture.webOne.id, from: fixture.index, includeSecrets: false)

    let refused = ConnectionsImport(file: file, under: nil, firstPosition: 0, keepCommands: false)
    #expect(refused.commands.map(\.path) == ["web-01"])
    #expect(refused.connections.first?.settings.beforeConnect == .inherit)

    let kept = ConnectionsImport(file: file, under: nil, firstPosition: 0, keepCommands: true)
    #expect(kept.connections.first?.settings.beforeConnect.ownValue?.arguments == "$HOST$")
}

@Test("A command that asks for a password is always removed")
func commandWithPasswordIsRemoved() throws {
    let file = try ConnectionsFile.decode(json("""
    {
      "format": "shellyard.connections", "version": 1,
      "items": [
        { "type": "connection", "name": "x", "host": "h",
          "settings": { "beforeConnect": { "program": "/bin/echo", "arguments": "$PASSWORD$" } } }
      ]
    }
    """))
    let plan = ConnectionsImport(file: file, under: nil, firstPosition: 0, keepCommands: true)
    #expect(plan.commands.isEmpty)
    #expect(plan.refusedCommands.count == 1)
    #expect(plan.connections.first?.settings.beforeConnect == .inherit)
}

@Test("An import into a folder puts the entries under it")
func importUnderFolder() {
    let parent = UUID()
    let file = ConnectionsFile(items: [
        .connection(Connection(name: "a", host: "a"), externalID: nil),
    ])
    let plan = ConnectionsImport(file: file, under: parent, firstPosition: 3, keepCommands: false)
    #expect(plan.connections.first?.parentID == parent)
    #expect(plan.connections.first?.position == 3)
}

@Test("The settings of the list survive a write and a read")
func listSettingsRoundTrip() throws {
    let file = ConnectionsFile(settings: NodeSettings(username: .value("systemio")), items: [])
    let read = try ConnectionsFile.decode(file.encoded())
    #expect(read.settings.username == .value("systemio"))
    #expect(read.settingsProblem == nil)
    // Without settings, the file has no settings field.
    let plain = try String(decoding: ConnectionsFile(items: []).encoded(), as: UTF8.self)
    #expect(!plain.contains("settings"))
}

@Test("An import writes the settings of the list into the items at the top")
func importTakesListSettings() throws {
    let file = try ConnectionsFile.decode(json("""
    { "format": "shellyard.connections", "version": 1,
      "settings": { "username": "systemio", "jumpHost": "bastion" },
      "items": [
        { "type": "connection", "name": "a", "host": "a", "settings": { "username": "root" } },
        { "type": "folder", "name": "F", "items": [ { "type": "connection", "name": "b", "host": "b" } ] }
      ] }
    """))
    let result = ConnectionsImport(file: file, under: nil, firstPosition: 0, keepCommands: false)
    let a = try #require(result.connections.first { $0.name == "a" })
    #expect(a.settings.username == .value("root"))
    #expect(a.settings.jumpHost == .value("bastion"))
    let folder = try #require(result.folders.first)
    #expect(folder.settings.username == .value("systemio"))
    // A deeper item inherits from its folder, as before.
    #expect(result.connections.first { $0.name == "b" }?.settings.username == .inherit)
}

@Test("Bad settings of the list are reported, and the items still come through")
func badListSettingsAreReported() throws {
    let file = try ConnectionsFile.decode(json("""
    { "format": "shellyard.connections", "version": 1,
      "settings": { "keepAliveSeconds": -5 },
      "items": [ { "type": "connection", "name": "a", "host": "a" } ] }
    """))
    #expect(file.settingsProblem != nil)
    #expect(file.settings == .inheritAll)
    let result = ConnectionsImport(file: file, under: nil, firstPosition: 0, keepCommands: false)
    #expect(result.problems.count == 1)
    #expect(result.connections.count == 1)
}
