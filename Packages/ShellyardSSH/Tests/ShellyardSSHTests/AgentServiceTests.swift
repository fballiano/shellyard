import Darwin
import Foundation
import Testing
@testable import ShellyardModel
@testable import ShellyardSSH

/// A socket path inside the per-user temporary directory, short enough for
/// a `sockaddr_un`.
private func temporarySocketPath() -> String {
    URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("ta-\(UUID().uuidString.prefix(8))/a.sock").path
}

@Test("The agent protocol carries a bookmark list back")
func agentListRoundTrip() async throws {
    let service = try AgentService(socketPath: temporarySocketPath())
    service.responder = { request in
        guard request.command == .list else { return .refused("wrong command") }
        return AgentReply(ok: true, bookmarks: [
            AgentBookmark(path: "Prod / Web", name: "web1"),
            AgentBookmark(path: "", name: "top"),
        ])
    }
    try service.start()
    defer { service.stop() }

    let path = service.socketURL.path
    let reply = await Task.detached {
        AgentClient.send(AgentRequest(command: .list), socketPath: path)
    }.value

    #expect(reply?.ok == true)
    #expect(reply?.bookmarks?.count == 2)
    #expect(reply?.bookmarks?.first?.path == "Prod / Web")
}

@Test("A run request carries awkward words across unchanged")
func agentRunCarriesWords() async throws {
    let service = try AgentService(socketPath: temporarySocketPath())
    service.responder = { request in
        // Echo the words back as the argv, so the test sees what arrived.
        AgentReply(ok: true, argv: request.words)
    }
    try service.start()
    defer { service.stop() }

    let awkward = ["echo", "a b", "it's", "läärm\n", "--", "-n"]
    let path = service.socketURL.path
    let reply = await Task.detached {
        AgentClient.send(
            AgentRequest(command: .run, bookmark: "web1", words: awkward),
            socketPath: path
        )
    }.value

    #expect(reply?.argv == awkward)
}

@Test("A refusal travels with its reason")
func agentRefusalCarriesReason() async throws {
    let service = try AgentService(socketPath: temporarySocketPath())
    service.responder = { _ in .refused("No bookmark is named \"nope\".") }
    try service.start()
    defer { service.stop() }

    let path = service.socketURL.path
    let reply = await Task.detached {
        AgentClient.send(AgentRequest(command: .run, bookmark: "nope"), socketPath: path)
    }.value

    #expect(reply?.ok == false)
    #expect(reply?.error == "No bookmark is named \"nope\".")
}

@Test("A stopped service answers nothing, like a locked document")
func agentStoppedServiceIsSilent() async throws {
    let service = try AgentService(socketPath: temporarySocketPath())
    service.responder = { _ in AgentReply(ok: true) }
    try service.start()
    service.stop()

    let path = service.socketURL.path
    let reply = await Task.detached {
        AgentClient.send(AgentRequest(command: .list), socketPath: path)
    }.value
    #expect(reply == nil)
}

@Test("A service with no responder refuses instead of hanging")
func agentNoResponderRefuses() async throws {
    let service = try AgentService(socketPath: temporarySocketPath())
    try service.start()
    defer { service.stop() }

    let path = service.socketURL.path
    let reply = await Task.detached {
        AgentClient.send(AgentRequest(command: .list), socketPath: path)
    }.value
    #expect(reply?.ok == false)
}

@Test("A second instance does not take the socket from a live one")
func agentSecondInstanceLeavesLiveSocket() async throws {
    // A second copy of the app (a UI test, a debug build) once took the
    // socket from the app in use, and `shellyard` found nobody there.
    let path = temporarySocketPath()
    let first = try AgentService(socketPath: path)
    first.responder = { _ in AgentReply(ok: true, bookmarks: []) }
    try first.start()
    defer { first.stop() }

    let second = try AgentService(socketPath: path)
    second.responder = { _ in .refused("second") }
    #expect(throws: AgentServiceError.self) { try second.start() }
    second.stop()

    let reply = await Task.detached {
        AgentClient.send(AgentRequest(command: .list), socketPath: path)
    }.value
    #expect(reply?.ok == true)
}

@Test("A socket file left behind by a crash does not block the start")
func agentReplacesStaleSocket() async throws {
    let path = temporarySocketPath()
    // Bind, then close without removing the file, as a killed process does.
    try FileManager.default.createDirectory(
        atPath: (path as NSString).deletingLastPathComponent,
        withIntermediateDirectories: true
    )
    let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
    var address = sockaddr_un()
    address.sun_family = sa_family_t(AF_UNIX)
    withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: Array(path.utf8)) }
    let bound = withUnsafePointer(to: &address) { pointer in
        pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
        }
    }
    close(descriptor)
    #expect(bound == 0)
    #expect(FileManager.default.fileExists(atPath: path))

    let service = try AgentService(socketPath: path)
    service.responder = { _ in AgentReply(ok: true) }
    try service.start()
    defer { service.stop() }

    let reply = await Task.detached {
        AgentClient.send(AgentRequest(command: .list), socketPath: path)
    }.value
    #expect(reply?.ok == true)
}

@Test("A stopping service leaves a socket file that is not its own")
func agentStopLeavesOtherSocket() async throws {
    let path = temporarySocketPath()
    let old = try AgentService(socketPath: path)
    try old.start()
    // Someone removed the file, and a new service now owns the path.
    unlink(path)
    let current = try AgentService(socketPath: path)
    current.responder = { _ in AgentReply(ok: true) }
    try current.start()
    defer { current.stop() }

    old.stop()

    let reply = await Task.detached {
        AgentClient.send(AgentRequest(command: .list), socketPath: path)
    }.value
    #expect(reply?.ok == true)
}

@Test("The default socket path fits a Unix socket address")
func agentDefaultPathIsShortEnough() {
    // A sockaddr_un holds 104 bytes of path on macOS.
    #expect(AgentSocket.defaultPath().utf8.count < 104)
}

@Test("The socket file is private to this account")
func agentSocketIsPrivate() throws {
    let service = try AgentService(socketPath: temporarySocketPath())
    try service.start()
    defer { service.stop() }

    let attributes = try FileManager.default.attributesOfItem(atPath: service.socketURL.path)
    #expect((attributes[.posixPermissions] as? Int) == 0o600)
    let directory = service.socketURL.deletingLastPathComponent().path
    let directoryAttributes = try FileManager.default.attributesOfItem(atPath: directory)
    #expect((directoryAttributes[.posixPermissions] as? Int) == 0o700)
}

@MainActor
@Test("The words of a command are quoted for the far shell")
func commandArgumentsQuoteWords() {
    let connection = SSHConnection(
        id: UUID(), name: "test",
        target: SSHTarget(host: "example.test", port: 22, settings: .fallback),
        sessionToken: "token", controlPath: "/tmp/t.sock", environment: [:]
    )
    let argv = connection.commandArguments(["echo", "a b", "it's"])

    #expect(argv.first == "/usr/bin/ssh")
    #expect(argv.contains("example.test"))
    // One argument for the far shell, every word quoted where it needs it.
    #expect(argv.last == "echo 'a b' 'it'\\''s'")
}
