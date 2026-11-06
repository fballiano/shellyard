import Foundation
import Testing
@testable import TermoraModel
@testable import TermoraSSH

/// Drives the real `ssh` binary against a real OpenSSH server.
///
/// The server is started by the test, on a high port, in its own directory.
/// Nothing in your `~/.ssh` is read or written.
@MainActor
@Suite(.serialized, .enabled(if: TestSSHServer.isAvailable))
final class SSHIntegrationTests {
    private let server: TestSSHServer
    private let helperPath: String
    private let engine: SSHEngine
    private let delegate = RecordingDelegate()

    init() throws {
        server = try TestSSHServer()
        helperPath = try TestAskpassHelper.build()
        engine = try SSHEngine(helperPath: helperPath)
        engine.delegate = delegate
    }

    deinit {
        server.shutDown()
        try? FileManager.default.removeItem(atPath: helperPath)
    }

    private func target(keyPath: String, passphrase: String) -> SSHTarget {
        var settings = EffectiveSettings.fallback
        settings.username = server.username
        settings.authentication = .privateKey(path: keyPath, passphrase: Secret(passphrase))
        settings.hostKeyPolicy = .acceptNew
        settings.keepAliveSeconds = 0
        return SSHTarget(
            host: "127.0.0.1",
            port: server.port,
            settings: settings,
            extraOptions: server.isolationOptions
        )
    }

    @Test("A control master connects, and a pane attaches to it without asking again")
    func masterConnectsAndPaneAttaches() async throws {
        let id = UUID()
        let connection = await engine.connect(
            id: id, name: "test", target: target(keyPath: server.plainKeyPath, passphrase: "")
        )
        #expect(connection.state == .connected, "The master must connect. Log: \(connection.log)")

        // A pane runs this command line. Running it here proves that a pane
        // reaches the far host through the master and needs no second answer.
        let arguments = SSHCommand.session(target: connection.target, controlPath: connection.controlPath)
        let result = await ProcessRunner.run(
            SSHCommand.executable, arguments + ["echo", "attached-ok"]
        )
        #expect(result.succeeded, "Attaching failed: \(result.errorOutput)")
        #expect(result.output.contains("attached-ok"))

        // Nothing was asked, because the key has no passphrase.
        #expect(delegate.questions.isEmpty)

        await engine.disconnect(id: id)
        #expect(connection.state == .disconnected)
    }

    @Test("A master that the server drops reports the loss once, and a new one connects")
    func droppedMasterReportsLoss() async throws {
        let id = UUID()
        let connection = await engine.connect(
            id: id, name: "test", target: target(keyPath: server.plainKeyPath, passphrase: "")
        )
        try #require(connection.state == .connected, "The master must connect. Log: \(connection.log)")

        var reasons: [String] = []
        connection.onLost = { reasons.append($0) }
        server.dropConnections()

        let deadline = ContinuousClock.now + .seconds(10)
        while reasons.isEmpty, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(reasons.count == 1, "The loss must be reported once. Log: \(connection.log)")
        #expect(!connection.isConnected)

        // A new master replaces the dead one under the same identifier.
        await engine.disconnect(id: id)
        let again = await engine.connect(
            id: id, name: "test", target: target(keyPath: server.plainKeyPath, passphrase: "")
        )
        #expect(again.state == .connected, "A new master must connect. Log: \(again.log)")
        #expect(again !== connection)

        // Termora's own close is not a loss.
        var closedReasons: [String] = []
        again.onLost = { closedReasons.append($0) }
        await engine.disconnect(id: id)
        try await Task.sleep(for: .milliseconds(300))
        #expect(closedReasons.isEmpty, "A close that Termora asked for is not a loss.")
        #expect(reasons.count == 1)
    }

    @Test("At launch, an orphaned master closes, a dead socket goes, and a live owner's master stays")
    func clearsLeftoverMasters() async throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("lm-\(UUID().uuidString.prefix(8))")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let target = target(keyPath: server.plainKeyPath, passphrase: "")

        // A master whose parent is gone: `sh` starts it in the background
        // and exits, so launchd adopts it, as after a crash of Termora.
        let orphanPath = directory.appendingPathComponent("tc-orphan1.sock").path
        let orphanLine = POSIXQuote.line(
            [SSHCommand.executable] + SSHCommand.master(target: target, controlPath: orphanPath)
        )
        let starter = Process()
        starter.executableURL = URL(fileURLWithPath: "/bin/sh")
        starter.arguments = ["-c", "\(orphanLine) </dev/null >/dev/null 2>&1 &"]
        try starter.run()
        starter.waitUntilExit()

        // A master whose parent still runs: this test. Another copy of
        // Termora that runs now looks the same.
        let ownedPath = directory.appendingPathComponent("tc-owned01.sock").path
        let owned = Process()
        owned.executableURL = URL(fileURLWithPath: SSHCommand.executable)
        owned.arguments = SSHCommand.master(target: target, controlPath: ownedPath)
        owned.standardError = Pipe()
        try owned.run()
        defer { if owned.isRunning { owned.terminate() } }

        // A socket that no master answers.
        let deadPath = directory.appendingPathComponent("tc-dead0001.sock").path
        try makeDeadSocket(at: deadPath)

        #expect(await waitForMaster(at: orphanPath), "The orphaned master did not start.")
        #expect(await waitForMaster(at: ownedPath), "The owned master did not start.")

        let outcome = await LeftoverMasters.clear(in: directory)
        #expect(outcome == .init(closedMasters: 1, removedSockets: 1))
        #expect(!(await isMaster(at: orphanPath)), "The orphaned master must close.")
        #expect(await isMaster(at: ownedPath), "A master with a live parent must stay.")
        #expect(!FileManager.default.fileExists(atPath: deadPath), "The dead socket must go.")
    }

    @Test("The answer of ssh -O check gives the pid of the master")
    func readsMasterPID() {
        #expect(LeftoverMasters.masterPID(in: "Master running (pid=4321)\r\n") == 4321)
        #expect(LeftoverMasters.masterPID(in: "Control socket connect: No such file") == nil)
    }

    private func isMaster(at path: String) async -> Bool {
        await ProcessRunner.run(
            SSHCommand.executable, ["-S", path, "-O", "check", "termora"], limit: 5
        ).succeeded
    }

    private func waitForMaster(at path: String) async -> Bool {
        for _ in 0..<100 {
            if await isMaster(at: path) { return true }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return false
    }

    /// Binds a Unix socket and closes it without removing the file, as a
    /// master that is killed does.
    private func makeDeadSocket(at path: String) throws {
        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        try #require(descriptor >= 0)
        defer { close(descriptor) }
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        try #require(bytes.count < MemoryLayout.size(ofValue: address.sun_path))
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            buffer.copyBytes(from: bytes)
        }
        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        try #require(result == 0, "bind failed: \(errno)")
    }

    @Test("The terminal description reaches the far host over the master")
    func installsTheTerminalDescription() async throws {
        try #require(FileManager.default.isExecutableFile(atPath: "/usr/bin/tic"))

        let id = UUID()
        let connection = await engine.connect(
            id: id, name: "test", target: target(keyPath: server.plainKeyPath, passphrase: "")
        )
        #expect(connection.state == .connected, "The master must connect. Log: \(connection.log)")

        // A directory of its own, so the test never writes into a real home.
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("terminfo-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }

        // xterm-256color, because every Mac holds that description. The name
        // does not matter here: the path it takes is the same one.
        let terminal = LocalTerminal(name: "xterm-256color")
        let source = try #require(await RemoteTerminfo.source(of: terminal))
        let result = await connection.run(
            RemoteTerminfo.installWords(for: terminal.name, directory: directory.path),
            limit: RemoteTerminfo.limit,
            input: source
        )

        #expect(result.succeeded, "The far tic failed: \(result.errorOutput)")
        // `tic` files a description under the first letter of its name.
        #expect(FileManager.default.fileExists(
            atPath: directory.appendingPathComponent("78/xterm-256color").path
        ))

        await engine.disconnect(id: id)
    }

    @Test("A locked key is opened with the stored passphrase, through the real helper")
    func passphraseComesFromTheStoredSecret() async throws {
        delegate.storedAnswer = server.passphrase

        let id = UUID()
        let connection = await engine.connect(
            id: id,
            name: "locked",
            target: target(keyPath: server.lockedKeyPath, passphrase: server.passphrase)
        )

        #expect(connection.state == .connected,
                "OpenSSH must take the passphrase from Termora. Log: \(connection.log)")
        // OpenSSH really did run termora-askpass and ask for the passphrase.
        #expect(delegate.questions.contains { if case .keyPassphrase = $0 { true } else { false } })

        await engine.disconnect(id: id)
    }

    @Test("A wrong passphrase fails instead of asking again and again")
    func wrongPassphraseFailsOnce() async throws {
        delegate.storedAnswer = "not the passphrase"

        let id = UUID()
        let connection = await engine.connect(
            id: id,
            name: "locked",
            target: target(keyPath: server.lockedKeyPath, passphrase: "not the passphrase")
        )

        guard case .failed = connection.state else {
            Issue.record("A wrong passphrase must fail. State: \(connection.state). Log: <<\(connection.log)>>")
            await engine.disconnect(id: id)
            return
        }
        await engine.disconnect(id: id)
    }

    @Test("A tunnel opens and closes on a live connection, with no reconnection")
    func portForwardingOnALiveConnection() async throws {
        let id = UUID()
        let connection = await engine.connect(
            id: id, name: "test", target: target(keyPath: server.plainKeyPath, passphrase: "")
        )
        #expect(connection.state == .connected)

        // Send a local port back to the test server itself, which is the one
        // thing certainly listening.
        let listenPort = Int.random(in: 21000 ... 60000)
        let forward = PortForward(
            kind: .local,
            listenPort: listenPort,
            destinationHost: "127.0.0.1",
            destinationPort: server.port
        )

        let added = await connection.addForward(forward)
        #expect(added.succeeded, "Opening the tunnel failed: \(added.errorOutput)")
        #expect(connection.activeForwards.contains(forward.id))

        // The far end answers with its SSH banner through the tunnel.
        let banner = await ProcessRunner.run("/usr/bin/nc", ["-w", "2", "127.0.0.1", String(listenPort)])
        #expect(banner.output.contains("SSH-2.0"), "The tunnel carried no traffic.")

        let cancelled = await connection.cancelForward(forward)
        #expect(cancelled.succeeded, "Closing the tunnel failed: \(cancelled.errorOutput)")
        #expect(!connection.activeForwards.contains(forward.id))

        // The connection itself is untouched.
        #expect(connection.state == .connected)
        await engine.disconnect(id: id)
    }

    @Test("A tunnel can be closed and opened again on the same connection")
    func tunnelSurvivesBeingToggled() async throws {
        let id = UUID()
        let connection = await engine.connect(
            id: id, name: "test", target: target(keyPath: server.plainKeyPath, passphrase: "")
        )
        #expect(connection.state == .connected)

        let listenPort = Int.random(in: 21000 ... 60000)
        let forward = PortForward(
            kind: .local, listenPort: listenPort,
            destinationHost: "127.0.0.1", destinationPort: server.port
        )

        // The switch in the inspector does exactly this, twice.
        for attempt in 1 ... 2 {
            #expect(await connection.addForward(forward).succeeded,
                    "Opening the tunnel failed on attempt \(attempt).")
            let banner = await ProcessRunner.run(
                "/usr/bin/nc", ["-w", "2", "127.0.0.1", String(listenPort)]
            )
            #expect(banner.output.contains("SSH-2.0"),
                    "The tunnel carried no traffic on attempt \(attempt).")

            #expect(await connection.cancelForward(forward).succeeded,
                    "Closing the tunnel failed on attempt \(attempt).")
            #expect(!connection.activeForwards.contains(forward.id))
        }

        #expect(connection.state == .connected, "The connection itself must be untouched.")
        await engine.disconnect(id: id)
    }

    @Test("A dynamic tunnel really works as a SOCKS proxy")
    func dynamicTunnelProxies() async throws {
        let id = UUID()
        let connection = await engine.connect(
            id: id, name: "test", target: target(keyPath: server.plainKeyPath, passphrase: "")
        )
        #expect(connection.state == .connected)

        let socksPort = Int.random(in: 21000 ... 60000)
        let proxy = PortForward(kind: .dynamic, listenPort: socksPort)
        #expect(await connection.addForward(proxy).succeeded)

        // Reach the test server through the proxy. `nc -X 5 -x` speaks SOCKS5.
        let banner = await ProcessRunner.run("/usr/bin/nc", [
            "-X", "5", "-x", "127.0.0.1:\(socksPort)",
            "-w", "4", "127.0.0.1", String(server.port),
        ])
        #expect(banner.output.contains("SSH-2.0"),
                "The SOCKS proxy carried no traffic. \(banner.errorOutput)")

        #expect(await connection.cancelForward(proxy).succeeded)
        await engine.disconnect(id: id)
    }

    @Test("A command from the `termora` tool runs over the master, and its exit code comes back")
    func agentCommandRunsOverTheMaster() async throws {
        let id = UUID()
        let connection = await engine.connect(
            id: id, name: "test", target: target(keyPath: server.plainKeyPath, passphrase: "")
        )
        #expect(connection.state == .connected, "The master must connect. Log: \(connection.log)")

        // The tool executes exactly this argv. A word with a space must
        // arrive at the far shell as one word.
        let argv = connection.commandArguments(["echo", "one word"])
        let result = await ProcessRunner.run(argv[0], Array(argv.dropFirst()))
        #expect(result.succeeded, "The command failed: \(result.errorOutput)")
        #expect(result.output.contains("one word"))

        // OpenSSH hands the far exit code back, and the tool exits with it.
        let failing = connection.commandArguments(["sh", "-c", "exit 7"])
        let failure = await ProcessRunner.run(failing[0], Array(failing.dropFirst()))
        #expect(failure.status == 7)

        await engine.disconnect(id: id)
    }

    @Test("The SFTP subsystem answers on the same connection")
    func sftpSubsystemOpens() async throws {
        let id = UUID()
        let connection = await engine.connect(
            id: id, name: "test", target: target(keyPath: server.plainKeyPath, passphrase: "")
        )
        #expect(connection.state == .connected)

        // Phase six will speak this protocol. For now, prove the channel opens
        // and the server sends its SFTP version packet.
        let process = Process()
        process.executableURL = URL(fileURLWithPath: SSHCommand.executable)
        process.arguments = connection.sftpArguments()
        let input = Pipe()
        let output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = Pipe()
        try process.run()

        // SSH_FXP_INIT: length 5, type 1, version 3.
        var packet = Data([0, 0, 0, 5, 1, 0, 0, 0, 3])
        input.fileHandleForWriting.write(packet)

        let reply = output.fileHandleForReading.readData(ofLength: 9)
        process.terminate()

        #expect(reply.count >= 5, "The server sent no SFTP answer.")
        // Byte 4 is the packet type. 2 is SSH_FXP_VERSION.
        #expect(reply.count >= 5 && reply[4] == 2, "Expected SSH_FXP_VERSION, got \(Array(reply))")
        packet.removeAll()

        await engine.disconnect(id: id)
    }
}

/// Records what OpenSSH asked, and answers with a fixed secret.
@MainActor
private final class RecordingDelegate: SSHEngineDelegate {
    var storedAnswer: String?
    var questions: [AskpassPrompt] = []

    func storedSecret(for connectionID: UUID, prompt: AskpassPrompt) -> String? {
        questions.append(prompt)
        return storedAnswer
    }

    func askPerson(connectionID: UUID, connectionName: String,
                   prompt: AskpassPrompt) async -> String? {
        questions.append(prompt)
        return storedAnswer
    }
}
