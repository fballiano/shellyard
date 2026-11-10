import Foundation
import Testing
@testable import ShellyardModel

/// A document with one synced folder, "Fleet", and one normal folder.
private struct Fixture {
    var document: Document
    let fleetID: UUID
    let otherID: UUID

    init(sync: FolderSync = FolderSync(url: "https://example.com/list.json")) {
        let fleet = Folder(name: "Fleet", position: 0, sync: sync)
        let other = Folder(name: "Other", position: 1)
        fleetID = fleet.id
        otherID = other.id
        document = Document(folders: [fleet, other])
    }

    func connection(_ externalID: String) -> Connection? {
        document.connections.first { $0.syncLink?.externalID == externalID }
    }

    func folder(_ externalID: String) -> Folder? {
        document.folders.first { $0.syncLink?.externalID == externalID }
    }

    var fleet: Folder { document.folders.first { $0.id == fleetID }! }

    func childNames(of parent: UUID) -> [String] {
        DocumentIndex(document).children(of: parent).map(\.name)
    }
}

private func file(_ json: String) throws -> ConnectionsFile {
    try ConnectionsFile.decode(Data("""
    { "format": "shellyard.connections", "version": 1, "items": \(json) }
    """.utf8))
}

private let firstList = """
[
  { "type": "connection", "id": "web-1", "name": "web-1", "host": "10.0.0.1",
    "settings": { "username": "deploy", "authentication": { "method": "password" } } },
  { "type": "folder", "id": "db", "name": "Databases", "items": [
      { "type": "connection", "id": "db-1", "name": "db-1", "host": "10.0.1.1", "port": 2222 }
  ] }
]
"""

// MARK: - Add, change, remove

@Test("The first sync adds every entry, with its place and its order")
func firstSyncAdds() throws {
    var fixture = Fixture()
    let report = try fixture.document.applySync(file(firstList), toFolder: fixture.fleetID)

    #expect(report.added == 3)
    #expect(fixture.childNames(of: fixture.fleetID) == ["web-1", "Databases"])
    let databases = try #require(fixture.folder("db"))
    #expect(fixture.connection("db-1")?.parentID == databases.id)
    #expect(fixture.connection("db-1")?.port == 2222)
    #expect(fixture.connection("web-1")?.syncLink?.sourceID == fixture.fleetID)
}

@Test("A second sync of the same list changes nothing")
func secondSyncIsQuiet() throws {
    var fixture = Fixture()
    try fixture.document.applySync(file(firstList), toFolder: fixture.fleetID)
    let before = fixture.document
    let report = try fixture.document.applySync(file(firstList), toFolder: fixture.fleetID)
    #expect(!report.changedSomething)
    #expect(report.keptLocalChanges.isEmpty)
    #expect(fixture.document.connections.map(\.id) == before.connections.map(\.id))
    #expect(fixture.document.connections.map(\.forwards) == before.connections.map(\.forwards))
}

@Test("A changed entry is changed, a new one added, and a missing one removed")
func addChangeRemove() throws {
    var fixture = Fixture()
    try fixture.document.applySync(file(firstList), toFolder: fixture.fleetID)
    let webID = try #require(fixture.connection("web-1")?.id)

    let report = try fixture.document.applySync(file("""
    [
      { "type": "connection", "id": "web-1", "name": "web-1", "host": "10.0.0.99",
        "settings": { "username": "deploy", "authentication": { "method": "password" } } },
      { "type": "connection", "id": "web-2", "name": "web-2", "host": "10.0.0.2" }
    ]
    """), toFolder: fixture.fleetID)

    #expect(report.added == 1)
    #expect(report.updated == 1)
    #expect(report.removed == 2)
    #expect(fixture.connection("web-1")?.id == webID, "A changed entry keeps its identity.")
    #expect(fixture.connection("web-1")?.host == "10.0.0.99")
    #expect(fixture.folder("db") == nil)
    #expect(fixture.connection("db-1") == nil)
    #expect(fixture.childNames(of: fixture.fleetID) == ["web-1", "web-2"])
}

@Test("An entry that moves to another folder in the list moves here too")
func entryMoves() throws {
    var fixture = Fixture()
    try fixture.document.applySync(file(firstList), toFolder: fixture.fleetID)
    try fixture.document.applySync(file("""
    [
      { "type": "folder", "id": "db", "name": "Databases", "items": [
          { "type": "connection", "id": "web-1", "name": "web-1", "host": "10.0.0.1" },
          { "type": "connection", "id": "db-1", "name": "db-1", "host": "10.0.1.1", "port": 2222 }
      ] }
    ]
    """), toFolder: fixture.fleetID)
    let databases = try #require(fixture.folder("db"))
    #expect(fixture.childNames(of: databases.id) == ["web-1", "db-1"])
}

// MARK: - Local changes stay

@Test("A field changed here keeps its value; the other fields follow the list")
func localChangesStay() throws {
    var fixture = Fixture()
    try fixture.document.applySync(file(firstList), toFolder: fixture.fleetID)
    let at = try #require(fixture.document.connections.firstIndex { $0.syncLink?.externalID == "web-1" })
    fixture.document.connections[at].name = "Web One"
    fixture.document.connections[at].isFavorite = true

    let report = try fixture.document.applySync(file("""
    [ { "type": "connection", "id": "web-1", "name": "web-1-renamed", "host": "10.0.0.5",
        "settings": { "username": "ops", "authentication": { "method": "password" } } } ]
    """), toFolder: fixture.fleetID)

    let web = try #require(fixture.connection("web-1"))
    #expect(web.name == "Web One", "The name was changed here, so it stays.")
    #expect(web.isFavorite)
    #expect(web.host == "10.0.0.5", "The host was not changed here, so it follows the list.")
    #expect(web.settings.username == .value("ops"))
    #expect(report.keptLocalChanges.map(\.path) == ["web-1-renamed"])

    // The next list sets the old name back. The local value still wins.
    try fixture.document.applySync(file("""
    [ { "type": "connection", "id": "web-1", "name": "web-1", "host": "10.0.0.5" } ]
    """), toFolder: fixture.fleetID)
    #expect(fixture.connection("web-1")?.name == "Web One")
}

@Test("A password typed here stays when the list sends none")
func typedPasswordStays() throws {
    var fixture = Fixture()
    try fixture.document.applySync(file(firstList), toFolder: fixture.fleetID)
    let at = try #require(fixture.document.connections.firstIndex { $0.syncLink?.externalID == "web-1" })
    fixture.document.connections[at].settings.authentication = .value(.password(Secret("typed")))

    try fixture.document.applySync(file(firstList), toFolder: fixture.fleetID)
    #expect(fixture.connection("web-1")?.settings.authentication == .value(.password(Secret("typed"))))
}

@Test("A password from the list arrives when none was typed")
func passwordFromTheList() throws {
    var fixture = Fixture()
    try fixture.document.applySync(file(firstList), toFolder: fixture.fleetID)
    try fixture.document.applySync(file("""
    [ { "type": "connection", "id": "web-1", "name": "web-1", "host": "10.0.0.1",
        "settings": { "username": "deploy",
                      "authentication": { "method": "password", "password": "from-api" } } } ]
    """), toFolder: fixture.fleetID)
    #expect(fixture.connection("web-1")?.settings.authentication
            == .value(.password(Secret("from-api"))))
}

@Test("A new method from the list replaces the old one, unless it was changed here")
func methodChange() {
    let base: Inherited<Authentication> = .value(.password(.empty))
    let remote: Inherited<Authentication> = .value(.privateKey(path: "~/.ssh/k", passphrase: .empty))
    // Only a password was typed: the method itself was not changed here.
    #expect(SyncEngine.mergeAuthentication(
        local: .value(.password(Secret("typed"))), base: base, remote: remote
    ) == .value(.privateKey(path: "~/.ssh/k", passphrase: .empty)),
            "The typed password belongs to the old method, so it does not move.")
    // The method was changed here: it stays.
    #expect(SyncEngine.mergeAuthentication(local: .value(.agent), base: base, remote: remote)
            == .value(.agent))
}

// MARK: - Nodes of the person

@Test("A node added by hand is never changed or removed")
func handMadeNodesStay() throws {
    var fixture = Fixture()
    try fixture.document.applySync(file(firstList), toFolder: fixture.fleetID)
    let mine = Connection(parentID: fixture.fleetID, name: "mine", position: 99, host: "my.host")
    fixture.document.add(mine)

    try fixture.document.applySync(file("""
    [ { "type": "connection", "id": "web-1", "name": "web-1", "host": "10.0.0.1" } ]
    """), toFolder: fixture.fleetID)
    #expect(fixture.document.connections.contains { $0.id == mine.id && $0.host == "my.host" })
    #expect(fixture.childNames(of: fixture.fleetID) == ["web-1", "mine"])
}

@Test("A node added by hand inside a removed folder moves to the synced folder")
func handMadeNodeSurvivesItsFolder() throws {
    var fixture = Fixture()
    try fixture.document.applySync(file(firstList), toFolder: fixture.fleetID)
    let databases = try #require(fixture.folder("db"))
    let mine = Connection(parentID: databases.id, name: "mine", host: "my.host")
    fixture.document.add(mine)

    try fixture.document.applySync(file("""
    [ { "type": "connection", "id": "web-1", "name": "web-1", "host": "10.0.0.1" } ]
    """), toFolder: fixture.fleetID)
    #expect(fixture.document.connections.first { $0.id == mine.id }?.parentID == fixture.fleetID)
}

@Test("An entry deleted here is not added again")
func deletedEntryStaysDeleted() throws {
    var fixture = Fixture()
    try fixture.document.applySync(file(firstList), toFolder: fixture.fleetID)
    let databases = try #require(fixture.folder("db"))
    fixture.document.excludeFromSync(nodesIn: databases.id)
    fixture.document.remove(id: databases.id)
    #expect(Set(fixture.fleet.sync?.excludedIDs ?? []) == ["db", "db-1"])

    let report = try fixture.document.applySync(file(firstList), toFolder: fixture.fleetID)
    #expect(report.added == 0)
    #expect(fixture.folder("db") == nil)
    #expect(fixture.connection("db-1") == nil)
}

@Test("An entry moved out of the folder stops syncing and is not added again")
func movedOutEntryStopsSyncing() throws {
    var fixture = Fixture()
    try fixture.document.applySync(file(firstList), toFolder: fixture.fleetID)
    let web = try #require(fixture.connection("web-1"))
    fixture.document.move(id: web.id, toParent: fixture.otherID, position: 0)

    let report = try fixture.document.applySync(file(firstList), toFolder: fixture.fleetID)
    let moved = try #require(fixture.document.connections.first { $0.id == web.id })
    #expect(moved.syncLink == nil)
    #expect(moved.parentID == fixture.otherID)
    #expect(report.added == 0)
    #expect(fixture.fleet.sync?.excludedIDs.contains("web-1") == true)
}

// MARK: - Safety

@Test("A list with a bad entry adds and changes, but removes nothing")
func badEntryStopsRemovals() throws {
    var fixture = Fixture()
    try fixture.document.applySync(file(firstList), toFolder: fixture.fleetID)
    let report = try fixture.document.applySync(file("""
    [
      { "type": "connection", "id": "web-1", "name": "web-1", "host": "10.0.0.7" },
      { "type": "connection", "name": "no-id", "host": "x" },
      { "type": "connection", "id": "bad", "name": "bad" }
    ]
    """), toFolder: fixture.fleetID)
    #expect(report.problems.count == 2)
    #expect(report.removed == 0)
    #expect(report.removalsSkipped == 2)
    #expect(fixture.connection("db-1") != nil)
    #expect(fixture.connection("web-1")?.host == "10.0.0.7")
}

@Test("An empty list does not wipe the folder")
func emptyListIsRefused() throws {
    var fixture = Fixture()
    try fixture.document.applySync(file(firstList), toFolder: fixture.fleetID)
    let before = fixture.document
    #expect(throws: SyncError.wouldRemoveEverything(3)) {
        try fixture.document.applySync(file("[]"), toFolder: fixture.fleetID)
    }
    #expect(fixture.document == before, "A refused sync changes nothing.")
}

@Test("An id used two times is reported, and only the first one is used")
func duplicateIDs() throws {
    var fixture = Fixture()
    let report = try fixture.document.applySync(file("""
    [
      { "type": "connection", "id": "x", "name": "first", "host": "a" },
      { "type": "connection", "id": "x", "name": "second", "host": "b" }
    ]
    """), toFolder: fixture.fleetID)
    #expect(report.added == 1)
    #expect(report.problems.count == 1)
    #expect(fixture.connection("x")?.name == "first")
}

@Test("Commands are removed unless the server is trusted")
func syncCommandsNeedPermission() throws {
    let list = """
    [ { "type": "connection", "id": "c", "name": "c", "host": "h",
        "settings": { "beforeConnect": { "program": "/usr/bin/true", "arguments": "$HOST$" } } } ]
    """
    var refused = Fixture()
    let report = try refused.document.applySync(file(list), toFolder: refused.fleetID)
    #expect(refused.connection("c")?.settings.beforeConnect == .inherit)
    #expect(report.removedCommands.count == 1)

    var allowed = Fixture(sync: FolderSync(url: "https://example.com", trustsServer: true))
    try allowed.document.applySync(file(list), toFolder: allowed.fleetID)
    #expect(allowed.connection("c")?.settings.beforeConnect.ownValue?.launchPath == "/usr/bin/true")
}

@Test("A command with a password mark is removed even when commands are allowed")
func syncPasswordCommandRemoved() throws {
    var fixture = Fixture(sync: FolderSync(url: "https://example.com", trustsServer: true))
    try fixture.document.applySync(file("""
    [ { "type": "connection", "id": "c", "name": "c", "host": "h",
        "settings": { "beforeConnect": { "program": "/bin/echo", "arguments": "$PASSWORD$" } } } ]
    """), toFolder: fixture.fleetID)
    #expect(fixture.connection("c")?.settings.beforeConnect == .inherit)
}

@Test("A sync into a folder that is not synced is refused")
func notSyncedFolder() throws {
    var fixture = Fixture()
    #expect(throws: SyncError.notSynced) {
        try fixture.document.applySync(file(firstList), toFolder: fixture.otherID)
    }
    #expect(throws: SyncError.folderNotFound) {
        try fixture.document.applySync(file(firstList), toFolder: UUID())
    }
}

// MARK: - Addresses and storage

@Test("Only https, or http to this Mac, is accepted", arguments: [
    ("https://inventory.example.com/shellyard.json", true),
    ("http://localhost:8080/list", true),
    ("http://127.0.0.1/list", true),
    ("http://inventory.example.com/list", false),
    ("ftp://example.com/list", false),
    ("not a url", false),
    ("", false),
])
func addressRules(url: String, accepted: Bool) {
    #expect((FolderSync(url: url).urlProblem == nil) == accepted)
}

@Test("The sync settings and links survive a save, and an old document still reads")
func syncFieldsRoundTrip() throws {
    var fixture = Fixture(sync: FolderSync(url: "https://example.com", username: "u",
                                           password: Secret("p"), interval: .hourly))
    try fixture.document.applySync(file(firstList), toFolder: fixture.fleetID)
    let data = try JSONEncoder().encode(fixture.document)
    let read = try JSONDecoder().decode(Document.self, from: data)
    #expect(read == fixture.document)

    let old = try JSONDecoder().decode(Document.self, from: Data("""
    {"formatVersion":1,"folders":[{"id":"\(UUID())","name":"F","position":0,"isExpanded":true,
      "settings":{"username":null,"authentication":null,"jumpHost":null,"colorTag":null,
        "agentForwarding":null,"compression":null,"keepAliveSeconds":null,"x11Forwarding":null,
        "hostKeyPolicy":null,"afterConnectText":null,"beforeConnect":null},
      "notes":""}],"connections":[]}
    """.utf8))
    #expect(old.folders.first?.sync == nil)
}

// MARK: - Findings of the review

@Test("Deleting a synced folder does not delete the entries that the list still has in it")
func excludedFolderKeepsItsChildren() throws {
    var fixture = Fixture()
    try fixture.document.applySync(file(firstList), toFolder: fixture.fleetID)
    // The person moves db-1 out of Databases, but keeps it in the synced
    // folder, then deletes Databases.
    let db1 = try #require(fixture.connection("db-1"))
    fixture.document.move(id: db1.id, toParent: fixture.fleetID, position: 9)
    let at = try #require(fixture.document.connections.firstIndex { $0.id == db1.id })
    fixture.document.connections[at].notes = "mine"
    let databases = try #require(fixture.folder("db"))
    fixture.document.excludeFromSync(nodesIn: databases.id)
    fixture.document.remove(id: databases.id)

    let report = try fixture.document.applySync(file(firstList), toFolder: fixture.fleetID)
    #expect(report.removed == 0)
    #expect(fixture.connection("db-1")?.id == db1.id)
    #expect(fixture.connection("db-1")?.notes == "mine")
    #expect(fixture.connection("db-1")?.parentID == fixture.fleetID)
    #expect(fixture.folder("db") == nil)
}

@Test("A list whose only entry was deleted here is not taken for an empty list")
func onlyExcludedEntryIsNotEmpty() throws {
    var fixture = Fixture()
    try fixture.document.applySync(file("""
    [ { "type": "connection", "id": "a", "name": "a", "host": "a" },
      { "type": "connection", "id": "b", "name": "b", "host": "b" } ]
    """), toFolder: fixture.fleetID)
    let a = try #require(fixture.connection("a"))
    fixture.document.excludeFromSync(nodesIn: a.id)
    fixture.document.remove(id: a.id)

    let report = try fixture.document.applySync(file("""
    [ { "type": "connection", "id": "a", "name": "a", "host": "a" } ]
    """), toFolder: fixture.fleetID)
    #expect(report.removed == 1)
    #expect(fixture.document.connections.isEmpty)
}

@Test("A secret never moves to another method")
func secretStaysWithItsMethod() {
    let typedPassword: Inherited<Authentication> = .value(.password(Secret("typed")))
    let toKey = SyncEngine.mergeAuthentication(
        local: typedPassword,
        base: .value(.password(.empty)),
        remote: .value(.privateKey(path: "~/.ssh/k", passphrase: .empty))
    )
    #expect(toKey == .value(.privateKey(path: "~/.ssh/k", passphrase: .empty)))

    let toPassword = SyncEngine.mergeAuthentication(
        local: .value(.privateKey(path: "~/.ssh/k", passphrase: Secret("typed"))),
        base: .value(.privateKey(path: "~/.ssh/k", passphrase: .empty)),
        remote: .value(.password(.empty))
    )
    #expect(toPassword == .value(.password(.empty)))

    // A method changed here keeps its own secret, whatever the list sends.
    let keptLocal = SyncEngine.mergeAuthentication(
        local: .value(.privateKey(path: "~/.ssh/mine", passphrase: Secret("pp"))),
        base: .value(.password(.empty)),
        remote: .value(.password(Secret("from-api")))
    )
    #expect(keptLocal == .value(.privateKey(path: "~/.ssh/mine", passphrase: Secret("pp"))))
}

@Test("A synced entry whose parent is gone is placed again, not excluded")
func lostEntryIsPlacedAgain() throws {
    var fixture = Fixture()
    try fixture.document.applySync(file(firstList), toFolder: fixture.fleetID)
    let at = try #require(fixture.document.connections.firstIndex { $0.syncLink?.externalID == "db-1" })
    fixture.document.connections[at].parentID = UUID()

    try fixture.document.applySync(file(firstList), toFolder: fixture.fleetID)
    #expect(fixture.connection("db-1")?.parentID == fixture.folder("db")?.id)
    #expect(fixture.fleet.sync?.excludedIDs.isEmpty == true)
}

@Test("Agent and X11 forwarding are removed unless the server is trusted")
func forwardingNeedsTrust() throws {
    let list = """
    [ { "type": "connection", "id": "c", "name": "c", "host": "h",
        "settings": { "agentForwarding": true, "x11Forwarding": true, "jumpHost": "bastion" } } ]
    """
    var untrusted = Fixture()
    try untrusted.document.applySync(file(list), toFolder: untrusted.fleetID)
    let settings = try #require(untrusted.connection("c")?.settings)
    #expect(settings.agentForwarding == .inherit)
    #expect(settings.x11Forwarding == .inherit)
    #expect(settings.jumpHost == .value("bastion"))

    var trusted = Fixture(sync: FolderSync(url: "https://example.com", trustsServer: true))
    try trusted.document.applySync(file(list), toFolder: trusted.fleetID)
    #expect(trusted.connection("c")?.settings.agentForwarding == .value(true))
}

@Test("Turning the sync off makes its entries normal, so a new address cannot remove them")
func releasedEntriesStay() throws {
    var fixture = Fixture()
    try fixture.document.applySync(file(firstList), toFolder: fixture.fleetID)
    fixture.document.releaseSyncedNodes(of: fixture.fleetID)
    #expect(fixture.document.connections.allSatisfy { $0.syncLink == nil })

    let report = try fixture.document.applySync(file("""
    [ { "type": "connection", "id": "other", "name": "other", "host": "o" } ]
    """), toFolder: fixture.fleetID)
    #expect(report.removed == 0)
    #expect(fixture.document.connections.map(\.name).sorted() == ["db-1", "other", "web-1"])
}

@Test("Edits in the editor change only the fields the person changed")
func editorWritesOnlyItsEdits() {
    var base = Connection(name: "web", host: "old.host",
                          settings: NodeSettings(username: .value("deploy")))
    base.notes = "n"
    var stored = base
    stored.host = "new.host"                       // a sync changed the host
    stored.settings.jumpHost = .value("bastion")   // and a setting
    stored.parentID = UUID()                       // and the place
    var draft = base
    draft.name = "Web One"                         // the person changed the name
    draft.settings.username = .value("ops")        // and another setting

    let result = stored.applyingEdits(of: draft, since: base)
    #expect(result.name == "Web One")
    #expect(result.host == "new.host")
    #expect(result.settings.username == .value("ops"))
    #expect(result.settings.jumpHost == .value("bastion"))
    #expect(result.parentID == stored.parentID)
}

// MARK: - The settings of the list

private func file(settings: String, items json: String = firstList) throws -> ConnectionsFile {
    try ConnectionsFile.decode(Data("""
    { "format": "shellyard.connections", "version": 1, "settings": \(settings), "items": \(json) }
    """.utf8))
}

@Test("The settings of the list become the settings of the synced folder")
func listSettingsGoToTheFolder() throws {
    var fixture = Fixture()
    let report = try fixture.document.applySync(
        file(settings: #"{ "username": "systemio", "keepAliveSeconds": 30 }"#), toFolder: fixture.fleetID
    )
    #expect(fixture.fleet.settings.username == .value("systemio"))
    #expect(fixture.fleet.settings.keepAliveSeconds == .value(30))
    #expect(fixture.fleet.sync?.settingsBase.username == .value("systemio"))
    #expect(report.updated == 1)

    // The connections inherit the user from the synced folder.
    let index = DocumentIndex(fixture.document)
    let db = try #require(fixture.connection("db-1"))
    #expect(index.effectiveSettings(for: db).username == "systemio")

    let again = try fixture.document.applySync(
        file(settings: #"{ "username": "systemio", "keepAliveSeconds": 30 }"#), toFolder: fixture.fleetID
    )
    #expect(!again.changedSomething)
}

@Test("A folder setting changed here stays; the other settings follow the list")
func folderSettingChangedHereStays() throws {
    var fixture = Fixture()
    try fixture.document.applySync(file(settings: #"{ "username": "systemio", "jumpHost": "bastion" }"#),
                                   toFolder: fixture.fleetID)
    let at = try #require(fixture.document.folders.firstIndex { $0.id == fixture.fleetID })
    fixture.document.folders[at].settings.username = .value("me")
    fixture.document.folders[at].settings.authentication = .value(.agent)

    try fixture.document.applySync(file(settings: #"{ "username": "ops", "jumpHost": "gate" }"#),
                                   toFolder: fixture.fleetID)
    #expect(fixture.fleet.settings.username == .value("me"))
    #expect(fixture.fleet.settings.jumpHost == .value("gate"))
    // The list never sent a method, so the method of the person stays.
    #expect(fixture.fleet.settings.authentication == .value(.agent))
}

@Test("A folder setting set by hand before the first sync stays")
func handSetFolderSettingStays() throws {
    var fixture = Fixture()
    let at = try #require(fixture.document.folders.firstIndex { $0.id == fixture.fleetID })
    fixture.document.folders[at].settings.username = .value("me")

    try fixture.document.applySync(file(settings: #"{ "username": "systemio" }"#), toFolder: fixture.fleetID)
    #expect(fixture.fleet.settings.username == .value("me"))
}

@Test("A setting that the list stops sending inherits again")
func droppedListSettingInherits() throws {
    var fixture = Fixture()
    try fixture.document.applySync(file(settings: #"{ "username": "systemio" }"#), toFolder: fixture.fleetID)
    try fixture.document.applySync(file(firstList), toFolder: fixture.fleetID)
    #expect(fixture.fleet.settings.username == .inherit)
    #expect(fixture.fleet.sync?.settingsBase == .inheritAll)
}

@Test("The settings of an untrusted list lose commands and forwarding")
func listSettingsNeedTrust() throws {
    var fixture = Fixture()
    let report = try fixture.document.applySync(file(settings: """
    { "agentForwarding": true, "beforeConnect": { "program": "/usr/bin/true" } }
    """), toFolder: fixture.fleetID)
    #expect(fixture.fleet.settings.agentForwarding == .inherit)
    #expect(fixture.fleet.settings.beforeConnect == .inherit)
    #expect(report.removedCommands.count == 2)
}

@Test("Bad settings in the list change no setting and remove nothing")
func badListSettings() throws {
    var fixture = Fixture()
    try fixture.document.applySync(file(settings: #"{ "username": "systemio" }"#), toFolder: fixture.fleetID)
    let report = try fixture.document.applySync(
        file(settings: #"{ "username": "ops", "keepAliveSeconds": -1 }"#, items: "[]"),
        toFolder: fixture.fleetID
    )
    #expect(fixture.fleet.settings.username == .value("systemio"))
    #expect(report.problems.count == 1)
    #expect(report.removed == 0)
    #expect(fixture.connection("web-1") != nil)
}

// MARK: - Synced entries that leave their synced folder

@Test("A synced folder moved out, then its synced folder deleted, becomes a normal folder")
func detachedFolderBecomesNormal() throws {
    var fixture = Fixture()
    try fixture.document.applySync(file(firstList), toFolder: fixture.fleetID)
    let databases = try #require(fixture.folder("db"))
    fixture.document.move(id: databases.id, toParent: nil, position: 9)
    fixture.document.remove(id: fixture.fleetID)

    fixture.document.releaseDetachedSyncedNodes()
    let freed = try #require(fixture.document.folders.first { $0.id == databases.id })
    #expect(freed.syncLink == nil)
    #expect(fixture.document.connections.allSatisfy { $0.syncLink == nil })
}

@Test("An entry moved out is released and excluded at once, before the next sync")
func movedOutIsReleasedAtOnce() throws {
    var fixture = Fixture()
    try fixture.document.applySync(file(firstList), toFolder: fixture.fleetID)
    let web = try #require(fixture.connection("web-1"))
    fixture.document.move(id: web.id, toParent: fixture.otherID, position: 0)

    fixture.document.releaseDetachedSyncedNodes()
    #expect(fixture.document.connections.first { $0.id == web.id }?.syncLink == nil)
    #expect(fixture.fleet.sync?.excludedIDs == ["web-1"])
    // The entries still inside keep their link.
    #expect(fixture.connection("db-1") != nil)
    #expect(fixture.folder("db") != nil)
}

@Test("The entries of a folder whose sync is off become normal")
func syncOffReleases() throws {
    var fixture = Fixture()
    try fixture.document.applySync(file(firstList), toFolder: fixture.fleetID)
    let at = try #require(fixture.document.folders.firstIndex { $0.id == fixture.fleetID })
    fixture.document.folders[at].sync = nil

    fixture.document.releaseDetachedSyncedNodes()
    #expect(fixture.document.connections.allSatisfy { $0.syncLink == nil })
    #expect(fixture.document.folders.allSatisfy { $0.syncLink == nil })
}

// MARK: - The place of the entries that the person added

private let threeServers = """
[
  { "type": "connection", "id": "a", "name": "a", "host": "a" },
  { "type": "connection", "id": "b", "name": "b", "host": "b" },
  { "type": "connection", "id": "c", "name": "c", "host": "c" }
]
"""

@Test("Entries added by hand keep their place among the synced ones")
func handMadeNodesKeepTheirPlace() throws {
    var fixture = Fixture()
    try fixture.document.applySync(file(threeServers), toFolder: fixture.fleetID)
    // a=0, b=1, c=2. "top" goes above a, "middle" between a and b.
    fixture.document.add(Connection(parentID: fixture.fleetID, name: "top", position: -1, host: "t"))
    fixture.document.add(Connection(parentID: fixture.fleetID, name: "middle", position: 1, host: "m"))
    let at = try #require(fixture.document.connections.firstIndex { $0.name == "b" })
    fixture.document.connections[at].position = 2
    let atC = try #require(fixture.document.connections.firstIndex { $0.name == "c" })
    fixture.document.connections[atC].position = 3
    #expect(fixture.childNames(of: fixture.fleetID) == ["top", "a", "middle", "b", "c"])

    try fixture.document.applySync(file(threeServers), toFolder: fixture.fleetID)
    #expect(fixture.childNames(of: fixture.fleetID) == ["top", "a", "middle", "b", "c"])

    // The list adds "new" after a, and removes a. "middle" moves up to the
    // nearest synced entry above it that is still there: none, so the top.
    try fixture.document.applySync(file("""
    [
      { "type": "connection", "id": "new", "name": "new", "host": "n" },
      { "type": "connection", "id": "b", "name": "b", "host": "b" },
      { "type": "connection", "id": "c", "name": "c", "host": "c" }
    ]
    """), toFolder: fixture.fleetID)
    #expect(fixture.childNames(of: fixture.fleetID) == ["top", "middle", "new", "b", "c"])
}

@Test("An entry added by hand below a synced entry stays below it when the list reorders")
func handMadeNodeFollowsItsSyncedNeighbour() throws {
    var fixture = Fixture()
    try fixture.document.applySync(file(threeServers), toFolder: fixture.fleetID)
    fixture.document.add(Connection(parentID: fixture.fleetID, name: "after-c", position: 99, host: "x"))

    try fixture.document.applySync(file("""
    [
      { "type": "connection", "id": "c", "name": "c", "host": "c" },
      { "type": "connection", "id": "a", "name": "a", "host": "a" },
      { "type": "connection", "id": "b", "name": "b", "host": "b" }
    ]
    """), toFolder: fixture.fleetID)
    #expect(fixture.childNames(of: fixture.fleetID) == ["c", "after-c", "a", "b"])
}
