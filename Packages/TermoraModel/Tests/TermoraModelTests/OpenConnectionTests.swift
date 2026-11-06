import Foundation
import Testing
@testable import TermoraModel

// MARK: - Typed addresses

@Test("A typed address reads as user, host, and port", arguments: [
    ("web1", "", "web1", nil),
    ("deploy@web1", "deploy", "web1", nil),
    ("web1.example.com:2222", "", "web1.example.com", 2222),
    ("deploy@10.0.0.5:22", "deploy", "10.0.0.5", 22),
    ("me@example.com@jump", "me@example.com", "jump", nil),
    ("::1", "", "::1", nil),
    ("root@[fe80::1%en0]:2200", "root", "fe80::1%en0", 2200),
    ("  web1  ", "", "web1", nil),
] as [(String, String, String, Int?)])
func readsAddress(text: String, username: String, host: String, port: Int?) throws {
    let address = try #require(QuickConnectAddress(text))
    #expect(address.username == username)
    #expect(address.host == host)
    #expect(address.port == port)
}

@Test("Text that is not an address, or that OpenSSH would read as an option, is refused",
      arguments: [
          "", "   ", "web 1", "@web1", "deploy@", "web1:", "web1:0", "web1:65536",
          "web1:ssh", "-oProxyCommand=sh", "-l@web1", "deploy@-web1", "[::1", "[::1]x",
          "web1/etc", "web\u{7}1",
      ])
func refusesAddress(text: String) {
    #expect(QuickConnectAddress(text) == nil)
}

@Test("The address is written back the way it was typed")
func writesAddress() {
    #expect(QuickConnectAddress("deploy@web1:2222")?.text == "deploy@web1:2222")
    #expect(QuickConnectAddress("web1")?.text == "web1")
    #expect(QuickConnectAddress("[::1]:2222")?.text == "[::1]:2222")
    #expect(QuickConnectAddress("::1")?.text == "::1")
}

// MARK: - Bookmark search

private struct SearchFixture {
    let prod = Folder(name: "Production")
    let staging = Folder(name: "Staging")
    var document: Document

    init() {
        document = Document(
            folders: [prod, staging],
            connections: [
                Connection(parentID: prod.id, name: "web-01", host: "web01.example.com"),
                Connection(parentID: staging.id, name: "web-01", host: "web01.staging.example.com"),
                Connection(parentID: prod.id, name: "Database", host: "db1.example.com",
                           isFavorite: true),
                Connection(name: "Café server", host: "10.0.0.7"),
                Connection(name: "backup-web", host: "bk.example.com"),
            ]
        )
    }

    func names(for query: String) -> [String] {
        BookmarkSearch.matches(for: query, in: DocumentIndex(document))
            .map { "\($0.connection.name) [\($0.folderPath)]" }
    }
}

@Test("A name that starts with the word comes before a name that only contains it")
func ranksNamePrefixFirst() {
    let names = SearchFixture().names(for: "web")
    #expect(names == [
        "web-01 [Production]", "web-01 [Staging]", "backup-web []",
    ])
}

@Test("Each word must match, in the name, the host, or the folder path")
func everyWordMustMatch() {
    let fixture = SearchFixture()
    #expect(fixture.names(for: "web staging") == ["web-01 [Staging]"])
    #expect(fixture.names(for: "db1") == ["Database [Production]"])
    #expect(fixture.names(for: "10.0.0") == ["Café server []"])
    #expect(fixture.names(for: "web nothing").isEmpty)
}

@Test("Case and accents do not count")
func foldsCaseAndAccents() {
    #expect(SearchFixture().names(for: "CAFE") == ["Café server []"])
}

@Test("A loose match is not a match: the letters must be next to each other")
func noScatteredMatch() {
    // w…e…b in order, but not together.
    #expect(SearchFixture().names(for: "wbe").isEmpty)
}

@Test("An empty query lists every bookmark, favourites first")
func emptyQueryListsAll() {
    let names = SearchFixture().names(for: "")
    #expect(names.first == "Database [Production]")
    #expect(names.count == 5)
}
