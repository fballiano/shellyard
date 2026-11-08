//
//  SessionsController.swift
//  Termora
//

import Foundation
import GhosttyTerminal
import Network
import SwiftUI
import TermoraModel
import TermoraSSH

/// One tab: a connection, and either the panes or the files open on it.
///
/// A local tab has no connection. Its panes run your login shell on this Mac.
@MainActor
final class TerminalTab: Identifiable, ObservableObject {
    enum Phase: Equatable {
        case connecting
        /// A command runs on this Mac before the connection opens.
        case running(String)
        case ready
        case failed(String)
    }

    /// What the tab shows. Both kinds travel on the same SSH connection.
    enum Kind: Equatable {
        case terminal
        case files
    }

    let id = UUID()
    var kind: Kind = .terminal
    /// Set for a files tab, once the connection is open.
    var browser: FileBrowserModel?
    /// What the command before connecting printed, as it prints it.
    @Published var commandLog: String = ""
    /// The bookmark the tab belongs to. `nil` for a local tab.
    let connectionID: UUID?
    /// The name of the bookmark, or "Local" for a local tab.
    let name: String
    let colorTag: ColorTag

    @Published var phase: Phase = .connecting
    @Published var root: PaneNode?
    @Published var focusedPaneID: UUID?
    /// Why the connection under a ready tab stopped, or `nil` while it runs.
    ///
    /// The phase stays `ready`, so the panes stay in the view tree and you
    /// can still read their last output. A bar over them offers Reconnect.
    @Published var lostReason: String?
    /// Reconnect or Try Again is at work.
    @Published var isReconnecting = false

    /// Why a tab you cannot see asks for a look.
    enum Attention: Equatable {
        /// A bell, or a command that ended with no exit code.
        case neutral
        /// A command ended with exit code 0.
        case success
        /// A command ended with any other exit code.
        case failure
    }

    /// Set when a hidden pane rings the bell or ends a long command. It goes
    /// when the tab comes into view. See `SessionsController.updateVisibility`.
    @Published var attention: Attention?

    init(connectionID: UUID, connectionName: String, colorTag: ColorTag) {
        self.connectionID = connectionID
        name = connectionName
        self.colorTag = colorTag
    }

    /// A tab for shells on this Mac.
    private init(localNamed name: String) {
        connectionID = nil
        self.name = name
        colorTag = .none
    }

    static func local() -> TerminalTab {
        TerminalTab(localNamed: "Local")
    }

    var isLocal: Bool { connectionID == nil }

    var panes: [TerminalSession] { root?.panes ?? [] }

    var focusedPane: TerminalSession? {
        panes.first { $0.id == focusedPaneID }
    }

    /// The name to show for the tab. A local tab shows the folder of its
    /// focused shell, so two local tabs can be told apart.
    var title: String {
        guard isLocal else { return name }
        return Self.folderName(focusedPane?.workingDirectory) ?? name
    }

    /// The last part of a path, or `~` for your home folder.
    static func folderName(_ path: String?) -> String? {
        guard let path, !path.isEmpty else { return nil }
        let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path
        let url = URL(fileURLWithPath: path).standardizedFileURL
        if url.path == home { return "~" }
        return url.lastPathComponent
    }

    var iconName: String {
        if isLocal { return "laptopcomputer" }
        return kind == .files ? "folder" : "terminal"
    }

    func adopt(_ session: TerminalSession) {
        root = PaneNode(session)
        focusedPaneID = session.id
        phase = .ready
    }

    func split(axis: Axis, with session: TerminalSession) {
        guard let root, let target = focusedPaneID else { return }
        if root.isPane(target) {
            // The root is the pane being split, so the root becomes a division.
            self.root = PaneNode(axis: axis, first: PaneNode(rootPane(root)), second: PaneNode(session))
        } else {
            root.split(paneID: target, axis: axis, with: session)
        }
        focusedPaneID = session.id
    }

    /// Puts a new session in the place of every pane, so the splits keep
    /// their shape. The focus moves to the session that replaces the
    /// focused pane.
    ///
    /// A surface cannot start a second process, so each pane needs a new
    /// session, and the old scrollback goes with the old one.
    func replacePanes(with make: () -> TerminalSession) {
        guard let root else { return }
        var replaced: [UUID: UUID] = [:]
        root.replacePanes { old in
            let new = make()
            replaced[old.id] = new.id
            return new
        }
        focusedPaneID = focusedPaneID.flatMap { replaced[$0] } ?? panes.first?.id
    }

    /// Closes a pane. Returns true when the tab has no panes left.
    func close(paneID: UUID) -> Bool {
        guard let root else { return true }
        if root.isPane(paneID) {
            self.root = nil
            return true
        }
        root.remove(paneID: paneID)
        if focusedPaneID == paneID {
            focusedPaneID = panes.first?.id
        }
        return panes.isEmpty
    }

    private func rootPane(_ node: PaneNode) -> TerminalSession {
        if case let .pane(session) = node.content { return session }
        fatalError("rootPane called on a division")
    }
}

/// A question from OpenSSH that is waiting for a person.
@MainActor
final class PromptRequest: Identifiable, ObservableObject {
    let id = UUID()
    let connectionName: String
    let prompt: AskpassPrompt
    private var continuation: CheckedContinuation<String?, Never>?

    init(connectionName: String, prompt: AskpassPrompt,
         continuation: CheckedContinuation<String?, Never>) {
        self.connectionName = connectionName
        self.prompt = prompt
        self.continuation = continuation
    }

    /// Answers once. A second call does nothing, so a sheet that closes twice
    /// cannot resume the same continuation again.
    func respond(_ answer: String?) {
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(returning: answer)
    }
}

/// A pane that asked to close while its program still runs. The view asks
/// before the pane goes.
struct PaneCloseRequest: Identifiable {
    let paneID: UUID
    var id: UUID { paneID }
}

/// Owns the tabs, the panes, and the SSH engine.
@MainActor
final class SessionsController: ObservableObject {
    @Published private(set) var tabs: [TerminalTab] = []
    @Published var selectedTabID: UUID?
    @Published var pendingPrompt: PromptRequest?
    @Published var errorMessage: String?
    @Published var paneCloseRequest: PaneCloseRequest?
    /// The Open Connection field (⌘O) is on screen.
    @Published var showsOpenPanel = false

    /// The remote files open in editors on this Mac. The controller outlives
    /// every browser view, because an editor stays open after its tab closes.
    let remoteEdits = RemoteEditController()

    private let store: DocumentStore
    private var engineStorage: SSHEngine?
    /// Connections typed into the Open Connection field. They are not in
    /// the document, so they live here while a tab uses them. They hold no
    /// secret: OpenSSH asks for one through the usual sheet.
    private var quickConnections: [UUID: Connection] = [:]
    private var engineError: String?

    /// Lives as long as the application, so it is never removed.
    private var wakeObserver: (any NSObjectProtocol)?

    init(store: DocumentStore) {
        self.store = store
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.recoverAfterWake() }
        }
    }

    /// Builds the SSH engine the first time a connection is opened.
    ///
    /// The engine binds a Unix socket, so it must not be built while the
    /// application is starting: no socket is needed until you connect, and
    /// work at start-up delays the first window.
    private var engine: SSHEngine? {
        if let engineStorage { return engineStorage }
        do {
            let engine = try SSHEngine(helperPath: Self.helperPath())
            engine.delegate = self
            engine.localTerminal = GhosttyEnvironment.localTerminal
            engineStorage = engine
            return engine
        } catch {
            engineError = error.localizedDescription
            return nil
        }
    }

    /// `termora-askpass` sits next to the application executable.
    private static func helperPath() -> String {
        Bundle.main.bundleURL
            .appendingPathComponent("Contents/MacOS/termora-askpass")
            .path
    }

    var selectedTab: TerminalTab? {
        tabs.first { $0.id == selectedTabID }
    }

    /// Chooses the tab at a position, for the ⌘1…⌘9 shortcuts.
    func selectTab(at index: Int) {
        guard tabs.indices.contains(index) else { return }
        selectedTabID = tabs[index].id
    }

    /// Moves the choice left or right, wrapping at the ends.
    func selectRelativeTab(_ offset: Int) {
        guard tabs.count > 1,
              let current = tabs.firstIndex(where: { $0.id == selectedTabID })
        else { return }
        let next = (current + offset % tabs.count + tabs.count) % tabs.count
        selectedTabID = tabs[next].id
    }

    /// What the sidebar shows beside a connection.
    enum ConnectionActivity {
        case none
        case connecting
        case live
    }

    /// The state of a connection's sessions, for the sidebar dot.
    func activity(for connectionID: UUID) -> ConnectionActivity {
        var found = ConnectionActivity.none
        for tab in tabs where tab.connectionID == connectionID {
            if tab.isReconnecting {
                found = .connecting
                continue
            }
            switch tab.phase {
            case .ready where tab.lostReason == nil: return .live
            case .connecting, .running: found = .connecting
            case .ready, .failed: break
            }
        }
        return found
    }

    /// Tells every observer that a tab changed its phase.
    ///
    /// A tab publishes its own phase, but the sidebar watches this
    /// controller, not every tab, so the controller says it too.
    private func tabPhaseChanged() {
        objectWillChange.send()
    }

    func sshConnection(for connectionID: UUID) -> SSHConnection? {
        engineStorage?.connection(for: connectionID)
    }

    // MARK: - Opening a connection

    /// Opens a file browser on a connection, in its own tab.
    ///
    /// The browser travels on the same control master, so it opens with no
    /// second question and does not disturb any terminal pane.
    func openFiles(connection: Connection) {
        open(connection: connection, kind: .files)
    }

    /// Opens a tab for a connection. The control master authenticates first,
    /// then the pane attaches to it and opens with no second question.
    func open(connection: Connection, kind: TerminalTab.Kind = .terminal) {
        guard let engine else {
            errorMessage = engineError ?? "The SSH engine did not start."
            return
        }
        engine.connectTimeout = .seconds(AppSettings.connectTimeoutSeconds)

        let settings = store.index.effectiveSettings(
            for: connection, fallback: AppSettings.connectionFallback
        )
        guard !connection.host.isEmpty else {
            errorMessage = "\(connection.name) has no host name."
            return
        }

        let tab = TerminalTab(
            connectionID: connection.id,
            connectionName: connection.name,
            colorTag: settings.colorTag
        )
        tab.kind = kind
        tabs.append(tab)
        selectedTabID = tab.id
        start(tab, on: connection, settings: settings, engine: engine)
    }

    /// Opens the connection under a tab that has no session yet: a new tab,
    /// or a tab whose first attempt failed.
    private func start(
        _ tab: TerminalTab, on connection: Connection,
        settings: EffectiveSettings, engine: SSHEngine
    ) {
        let kind = tab.kind
        // A second tab on a live master opens no new connection. The command
        // before connecting and the tunnels already ran for the first tab.
        let alreadyOpen = engine.connection(for: connection.id)?.isConnected ?? false

        Task {
            // Royal TSX calls this a task. It runs on this Mac before the
            // connection opens, for example to open a firewall.
            if !alreadyOpen, !settings.beforeConnect.isEmpty {
                tab.phase = .running(settings.beforeConnect.name)
                tabPhaseChanged()
                tab.commandLog = ""
                let outcome = await LocalCommandRunner.run(
                    settings.beforeConnect,
                    values: CommandPlaceholders.Values(
                        host: connection.host,
                        port: connection.port ?? 22,
                        username: settings.username,
                        name: connection.name
                    ),
                    onOutput: { piece in
                        Task { @MainActor in tab.commandLog += piece }
                    }
                )
                if let problem = outcome.problem {
                    tab.phase = .failed(problem)
                    tabPhaseChanged()
                    return
                }
            }

            let sshConnection = await connectMaster(connection, settings: settings, engine: engine)

            switch sshConnection.state {
            case .connected:
                switch kind {
                case .terminal:
                    let session = makeSession(on: sshConnection, title: connection.name)
                    tab.adopt(session)
                    tabPhaseChanged()
                    // A tab may become ready while you are looking at another
                    // one. Tell the new pane whether it is on screen.
                    updateVisibility()
                    await typeAfterConnect(settings.afterConnectText, into: session)
                case .files:
                    tab.browser = makeBrowser(on: sshConnection)
                    tab.phase = .ready
                    tabPhaseChanged()
                }
                if !alreadyOpen { await startForwards(of: connection, on: sshConnection) }
            case let .failed(reason):
                tab.phase = .failed(reason)
                tabPhaseChanged()
            default:
                tab.phase = .failed("The connection did not open.")
                tabPhaseChanged()
            }
        }
    }

    /// What OpenSSH gets for a connection. A connection with no port sends
    /// none, so an alias keeps the port of `~/.ssh/config`.
    private func target(for connection: Connection, settings: EffectiveSettings) -> SSHTarget {
        SSHTarget(host: connection.host, port: connection.port, settings: settings)
    }

    /// Starts the control master, or returns the live one, and listens for
    /// its loss. Every path that opens a master comes through here.
    private func connectMaster(
        _ connection: Connection, settings: EffectiveSettings, engine: SSHEngine
    ) async -> SSHConnection {
        let sshConnection = await engine.connect(
            id: connection.id, name: connection.name,
            target: target(for: connection, settings: settings)
        )
        let connectionID = connection.id
        sshConnection.onLost = { [weak self] reason in
            self?.connectionLost(connectionID, reason: reason)
        }
        return sshConnection
    }

    private func makeBrowser(on sshConnection: SSHConnection) -> FileBrowserModel {
        let browser = FileBrowserModel(sshConnection: sshConnection)
        browser.onEdit = { [weak self] entry, application in
            self?.remoteEdits.edit(entry, on: sshConnection, with: application)
        }
        return browser
    }

    // MARK: - A lost connection

    /// The master stopped by itself. Every tab on it keeps its panes, so the
    /// last output can still be read, and shows a bar with Reconnect.
    ///
    /// An edit in progress ends: its save could never be copied back.
    private func connectionLost(_ connectionID: UUID, reason: String) {
        remoteEdits.connectionClosed(connectionID)
        for tab in tabs where tab.connectionID == connectionID && tab.phase == .ready {
            tab.lostReason = reason
        }
        tabPhaseChanged()
    }

    // MARK: - After a sleep

    /// Brings back the connections that a sleep of this Mac broke.
    ///
    /// With "lock on sleep" on, the document is locked and nothing is open,
    /// so there is nothing to do. Otherwise a connection is often lost by
    /// now, or worse, looks open while it no longer reaches the server:
    /// OpenSSH finds that out only through keep-alive, minutes later.
    private func recoverAfterWake() {
        guard store.isUnlocked else { return }
        let ids = Set(tabs.filter { !$0.isLocal && $0.phase == .ready }.compactMap(\.connectionID))
        guard !ids.isEmpty else { return }

        Task {
            // Wi-Fi takes a few seconds to come back. A reconnect before
            // that fails with "Could not resolve hostname".
            await NetworkWait.untilOnline(limit: .seconds(30))
            for id in ids {
                Task { await recoverAfterWake(id) }
            }
        }
    }

    private func recoverAfterWake(_ connectionID: UUID) async {
        if let sshConnection = engineStorage?.connection(for: connectionID),
           sshConnection.isConnected {
            // The master runs on this Mac, so only the server can say that
            // the connection still works.
            if await sshConnection.run(["true"], limit: 10).succeeded { return }
            await engineStorage?.disconnect(id: connectionID)
            connectionLost(connectionID, reason: "The connection did not survive the sleep of this Mac.")
        }
        guard store.isUnlocked,
              let tab = tabs.first(where: { $0.connectionID == connectionID && $0.lostReason != nil })
        else { return }
        reconnect(tab)
    }

    /// True when the tab can connect again: its connection was lost, or its
    /// first attempt failed.
    func canReconnect(_ tab: TerminalTab) -> Bool {
        guard !tab.isLocal, !tab.isReconnecting, connection(of: tab) != nil else { return false }
        if tab.lostReason != nil { return true }
        if case .failed = tab.phase { return true }
        return false
    }

    /// The Reconnect command (⌘R), for the tab in front.
    func reconnectSelectedTab() {
        guard let tab = selectedTab else { return }
        reconnect(tab)
    }

    /// Connects a tab again, after a loss or after a failed first attempt.
    func reconnect(_ tab: TerminalTab) {
        guard canReconnect(tab), let connection = connection(of: tab), let engine else { return }

        if case .failed = tab.phase {
            // Nothing was ever open in this tab: try the first attempt again.
            tab.phase = .connecting
            tab.commandLog = ""
            tabPhaseChanged()
            let settings = store.index.effectiveSettings(
                for: connection, fallback: AppSettings.connectionFallback
            )
            start(tab, on: connection, settings: settings, engine: engine)
            return
        }

        // Every tab on the lost master comes back on one new master.
        let affected = tabs.filter { $0.connectionID == connection.id && $0.lostReason != nil }
        for each in affected { each.isReconnecting = true }
        tabPhaseChanged()

        Task {
            // A new tab may already have opened a live master (⌘T on a lost
            // tab). Use it. Otherwise drop the dead master and its askpass
            // token first, or the engine would hand the dead one back.
            let current = engine.connection(for: connection.id)
            if current?.isConnected != true, current?.state != .connecting {
                await engine.disconnect(id: connection.id)
            }
            let outcome = await establish(connection)
            for each in affected { each.isReconnecting = false }

            switch outcome {
            case let .failure(reason):
                for each in affected { each.lostReason = reason }
            case let .success(sshConnection):
                let settings = store.index.effectiveSettings(
                    for: connection, fallback: AppSettings.connectionFallback
                )
                let open = affected.filter { each in tabs.contains { $0 === each } }
                for each in open {
                    switch each.kind {
                    case .terminal:
                        each.replacePanes { makeSession(on: sshConnection, title: each.name) }
                        if let pane = each.focusedPane {
                            Task { await typeAfterConnect(settings.afterConnectText, into: pane) }
                        }
                    case .files:
                        each.browser?.close()
                        each.browser = makeBrowser(on: sshConnection)
                    }
                    each.lostReason = nil
                }
                // Every tab closed while the master was opening.
                if !tabs.contains(where: { $0.connectionID == connection.id }) {
                    await engine.disconnect(id: connection.id)
                }
                updateVisibility()
                selectedTab?.focusedPane?.focus()
            }
            tabPhaseChanged()
        }
    }

    // MARK: - Quick connections

    /// Opens a tab on an address that has no bookmark.
    ///
    /// The connection takes the default settings, with the user name of the
    /// address. Nothing is written to the document.
    func openQuick(_ address: QuickConnectAddress, kind: TerminalTab.Kind = .terminal) {
        let connection = Connection(
            name: address.text,
            host: address.host,
            port: address.port,
            settings: NodeSettings(
                username: address.username.isEmpty ? .inherit : .value(address.username)
            )
        )
        quickConnections[connection.id] = connection
        open(connection: connection, kind: kind)
    }

    /// True when the tab runs on a typed address that is not a bookmark yet.
    func isQuick(_ tab: TerminalTab) -> Bool {
        guard let id = tab.connectionID else { return false }
        return quickConnections[id] != nil && store.index.connection(id) == nil
    }

    /// Makes a bookmark of the address that a quick tab runs on.
    ///
    /// The bookmark keeps the identifier of the quick connection, so the open
    /// tabs belong to it at once: the sidebar shows them as live, and ⌘T
    /// opens the same connection again.
    func saveAsBookmark(_ tab: TerminalTab) {
        guard isQuick(tab), let id = tab.connectionID, let quick = quickConnections[id] else {
            return
        }
        store.addBookmark(quick)
        quickConnections[id] = nil
    }

    // MARK: - Local tabs

    /// Opens a tab with your login shell on this Mac.
    ///
    /// The shell starts in `directory`, or in your home folder.
    func openLocal(in directory: String? = nil) {
        let tab = TerminalTab.local()
        tab.adopt(makeLocalSession(in: directory))
        tabs.append(tab)
        selectedTabID = tab.id
        updateVisibility()
    }

    /// The ⌘T command.
    ///
    /// On a connection tab, it opens a terminal on the same connection. On a
    /// local tab, it opens a local shell in the same folder. With no tab, or
    /// when the bookmark is gone, it opens a local shell in your home folder.
    func newTab() {
        guard let tab = selectedTab else {
            openLocal()
            return
        }
        if let connection = connection(of: tab) {
            open(connection: connection, kind: .terminal)
        } else {
            openLocal(in: tab.isLocal ? tab.focusedPane?.workingDirectory : nil)
        }
    }

    private func startForwards(of connection: Connection, on sshConnection: SSHConnection) async {
        let clashing = connection.clashingForwardIDs
        for forward in connection.forwards
        where forward.isEnabled && forward.isReady && !clashing.contains(forward.id) {
            let result = await sshConnection.addForward(forward)
            if !result.succeeded {
                errorMessage = "Termora could not open the tunnel \(forward.summary) "
                    + "on \(connection.name). \(result.summary)"
            }
        }
    }

    // MARK: - Agent access

    /// Every open connection, for `termora status`.
    var liveConnections: [SSHConnection] {
        guard let engineStorage else { return [] }
        return engineStorage.connections.values.sorted { $0.name < $1.name }
    }

    /// What `establish` produced. A refusal carries the words the tool
    /// prints on standard error.
    enum AgentConnectOutcome {
        case success(SSHConnection)
        case failure(String)
    }

    /// Opens or reuses the control master without a tab, for the `termora`
    /// tool and for Reconnect. When OpenSSH must ask, the askpass sheet
    /// appears here in the application, and the tool waits.
    func establish(_ connection: Connection) async -> AgentConnectOutcome {
        guard let engine else {
            return .failure(engineError ?? "The SSH engine did not start.")
        }
        guard !connection.host.isEmpty else {
            return .failure("\(connection.name) has no host name.")
        }
        engine.connectTimeout = .seconds(AppSettings.connectTimeoutSeconds)
        let settings = store.index.effectiveSettings(
            for: connection, fallback: AppSettings.connectionFallback
        )

        // The command before connecting belongs to a fresh connection only.
        // A live master was already paid for, command included.
        let alreadyOpen = engine.connection(for: connection.id)?.isConnected ?? false
        if !alreadyOpen, !settings.beforeConnect.isEmpty {
            let outcome = await LocalCommandRunner.run(
                settings.beforeConnect,
                values: CommandPlaceholders.Values(
                    host: connection.host,
                    port: connection.port ?? 22,
                    username: settings.username,
                    name: connection.name
                ),
                onOutput: { _ in }
            )
            if let problem = outcome.problem {
                return .failure("\(settings.beforeConnect.name): \(problem)")
            }
        }

        let sshConnection = await connectMaster(connection, settings: settings, engine: engine)
        switch sshConnection.state {
        case .connected:
            if !alreadyOpen { await startForwards(of: connection, on: sshConnection) }
            return .success(sshConnection)
        case let .failed(reason):
            return .failure(reason)
        default:
            return .failure("The connection did not open.")
        }
    }

    // MARK: - Tunnels on a live connection

    /// True when the connection is open, so its tunnels can be changed now.
    func isLive(connectionID: UUID) -> Bool {
        engineStorage?.connection(for: connectionID)?.isConnected ?? false
    }

    func isForwardActive(_ forward: PortForward, on connectionID: UUID) -> Bool {
        engineStorage?.connection(for: connectionID)?.activeForwards.contains(forward.id) ?? false
    }

    /// Opens or closes one tunnel without touching the connection.
    ///
    /// OpenSSH adds and cancels a tunnel on the control socket, so nothing is
    /// reconnected and no session is disturbed.
    func setForward(_ forward: PortForward, on connectionID: UUID, active: Bool) async {
        guard let sshConnection = engineStorage?.connection(for: connectionID),
              sshConnection.isConnected
        else { return }

        if active, let problem = forward.problem {
            errorMessage = "That tunnel is not ready. \(problem)"
            return
        }

        let result = active
            ? await sshConnection.addForward(forward)
            : await sshConnection.cancelForward(forward)

        if !result.succeeded {
            errorMessage = active
                ? "Termora could not open the tunnel \(forward.summary). \(result.summary)"
                : "Termora could not close the tunnel \(forward.summary). \(result.summary)"
        }
    }

    /// Types the text a connection carries, once the session is open.
    private func typeAfterConnect(_ text: String, into session: TerminalSession) async {
        let steps = KeySequence.steps(from: text)
        guard !steps.isEmpty else { return }

        // The pane opens before the prompt appears, and some shells (fish)
        // drop what arrives while they start.
        await session.waitForPrompt()
        for step in steps {
            switch step {
            case let .text(piece):
                session.send(piece)
            case let .press(key):
                session.press(Self.terminalKey(for: key))
            case let .wait(milliseconds):
                try? await Task.sleep(for: .milliseconds(milliseconds))
            }
        }
    }

    private static func terminalKey(for key: KeySequence.Key) -> TerminalKey {
        switch key {
        case .enter: .enter
        case .tab: .tab
        case .escape: .escape
        case .backspace: .backspace
        case .up: .arrowUp
        case .down: .arrowDown
        case .left: .arrowLeft
        case .right: .arrowRight
        }
    }

    private func makeSession(on sshConnection: SSHConnection, title: String) -> TerminalSession {
        wire(TerminalSession(launch: TerminalLaunch(
            command: sshConnection.terminalCommandLine(),
            waitAfterCommand: true,
            title: title
        )))
    }

    /// A login shell on this Mac. When the shell exits, its pane closes, the
    /// way it does in Ghostty.
    private func makeLocalSession(in directory: String?) -> TerminalSession {
        var launch = TerminalLaunch.loginShell
        launch.workingDirectory = Self.existingDirectory(directory)
            ?? FileManager.default.homeDirectoryForCurrentUser.path
        return wire(TerminalSession(launch: launch))
    }

    /// The folder, if it is still a folder on this Mac.
    private static func existingDirectory(_ path: String?) -> String? {
        guard let path, !path.isEmpty else { return nil }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else { return nil }
        return path
    }

    private func wire(_ session: TerminalSession) -> TerminalSession {
        session.onRequestClose = { [weak self] session, processAlive in
            guard let self else { return }
            // A pane whose program still runs is not closed on the spot: the
            // view asks first. A finished pane goes at once, except on a lost
            // connection: Ghostty asks to close on any key there, and the
            // pane must stay under the bar until you choose Reconnect.
            if processAlive {
                paneCloseRequest = PaneCloseRequest(paneID: session.id)
            } else if tab(containing: session.id)?.lostReason == nil {
                close(paneID: session.id)
            }
        }
        session.onEvent = { [weak self] session, event in
            self?.paneEvent(event, in: session)
        }
        return session
    }

    /// Marks the tab of a pane that needs a look. A tab in view needs no
    /// mark. The last event wins.
    private func paneEvent(_ event: PaneEvent, in session: TerminalSession) {
        guard let tab = tab(containing: session.id), tab.id != selectedTabID else { return }
        tab.attention = switch event {
        case .bell: .neutral
        case let .commandFinished(exitCode):
            switch exitCode {
            case nil: .neutral
            case 0: .success
            default: .failure
            }
        }
    }

    // MARK: - Panes and tabs

    func splitFocusedPane(axis: Axis) {
        guard let tab = selectedTab, tab.kind == .terminal, tab.phase == .ready else { return }
        if tab.isLocal {
            tab.split(axis: axis, with: makeLocalSession(in: tab.focusedPane?.workingDirectory))
        } else {
            guard let connectionID = tab.connectionID,
                  let sshConnection = engineStorage?.connection(for: connectionID),
                  sshConnection.isConnected
            else { return }
            tab.split(axis: axis, with: makeSession(on: sshConnection, title: tab.name))
        }
        updateVisibility()
    }

    private func tab(containing paneID: UUID) -> TerminalTab? {
        tabs.first { $0.panes.contains { $0.id == paneID } }
    }

    func close(paneID: UUID) {
        guard let tab = tab(containing: paneID) else { return }
        if tab.close(paneID: paneID) {
            closeTab(tab.id)
        }
        updateVisibility()
    }

    /// The bookmark a tab belongs to, if it is still in the document.
    func connection(of tab: TerminalTab) -> Connection? {
        tab.connectionID.flatMap { store.index.connection($0) ?? quickConnections[$0] }
    }

    /// True when `duplicate(_:)` can open something for the tab.
    func canDuplicate(_ tab: TerminalTab) -> Bool {
        tab.isLocal || connection(of: tab) != nil
    }

    /// Opens a second tab on the same bookmark, of the same kind. A local tab
    /// gets a second local shell in the same folder.
    func duplicate(_ tab: TerminalTab) {
        if tab.isLocal {
            openLocal(in: tab.focusedPane?.workingDirectory)
            return
        }
        guard let connection = connection(of: tab) else { return }
        open(connection: connection, kind: tab.kind)
    }

    /// Opens the file browser for the bookmark a tab belongs to.
    func openFiles(for tab: TerminalTab) {
        guard let connection = connection(of: tab) else { return }
        openFiles(connection: connection)
    }

    func closeOtherTabs(than tabID: UUID) {
        for other in tabs where other.id != tabID { closeTab(other.id) }
    }

    /// Closes every tab, every connection, and every edit. The document
    /// store calls this before it locks, so a locked document never leaves a
    /// live session or tunnel behind it.
    ///
    /// The tabs are not enough: `termora run` keeps masters with no tab.
    func closeEverything() {
        for id in tabs.map(\.id) { closeTab(id) }
        remoteEdits.endAll()
        if let engineStorage {
            Task { await engineStorage.disconnectAll() }
        }
    }

    /// True while any master is open, with or without a tab.
    var hasConnections: Bool {
        !(engineStorage?.connections.isEmpty ?? true)
    }

    func closeSelectedTab() {
        guard let selectedTabID else { return }
        closeTab(selectedTabID)
    }

    func closeTab(_ tabID: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == tabID }) else { return }
        let tab = tabs.remove(at: index)
        tab.browser?.close()

        // Close the connection when no other tab is using it. Its edits end
        // too: with the master gone, a save could never be copied back.
        if let connectionID = tab.connectionID,
           !tabs.contains(where: { $0.connectionID == connectionID }),
           let engineStorage {
            quickConnections[connectionID] = nil
            remoteEdits.connectionClosed(connectionID)
            Task { await engineStorage.disconnect(id: connectionID) }
        }

        if selectedTabID == tabID {
            selectedTabID = tabs.indices.contains(index) ? tabs[index].id : tabs.last?.id
        }
        updateVisibility()
    }

    func focus(paneID: UUID, in tab: TerminalTab) {
        tab.focusedPaneID = paneID
        tab.panes.first { $0.id == paneID }?.focus()
    }

    /// Stops drawing panes in tabs you cannot see. The grid, the scrollback,
    /// and the process all stay alive. The tab in view loses its mark.
    func updateVisibility() {
        for tab in tabs {
            let isVisible = tab.id == selectedTabID
            for pane in tab.panes { pane.setVisible(isVisible) }
            if isVisible, tab.attention != nil { tab.attention = nil }
        }
    }

    func disconnectEverything() async {
        remoteEdits.endAll()
        await engineStorage?.disconnectAll()
    }
}

// MARK: - Answering OpenSSH

extension SessionsController: SSHEngineDelegate {
    func storedSecret(for connectionID: UUID, prompt: AskpassPrompt) -> String? {
        guard let connection = store.index.connection(connectionID) else { return nil }
        let settings = store.index.effectiveSettings(
            for: connection, fallback: AppSettings.connectionFallback
        )

        switch (prompt, settings.authentication) {
        case let (.password, .password(secret)):
            return secret.isEmpty ? nil : secret.value
        case let (.keyPassphrase, .privateKey(_, passphrase)):
            return passphrase.isEmpty ? nil : passphrase.value
        default:
            return nil
        }
    }

    func askPerson(connectionID: UUID, connectionName: String,
                   prompt: AskpassPrompt) async -> String? {
        await withCheckedContinuation { continuation in
            pendingPrompt = PromptRequest(
                connectionName: connectionName,
                prompt: prompt,
                continuation: continuation
            )
        }
    }
}

/// Waits for a network path, for the reconnect after a sleep.
private enum NetworkWait {
    /// Returns when this Mac has a usable network path, or after `limit`.
    static func untilOnline(limit: Duration) async {
        let monitor = NWPathMonitor()
        let statuses = AsyncStream<NWPath.Status> { continuation in
            monitor.pathUpdateHandler = { continuation.yield($0.status) }
            continuation.onTermination = { _ in monitor.cancel() }
            monitor.start(queue: DispatchQueue(label: "Termora.NetworkWait"))
        }
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                for await status in statuses where status == .satisfied { return }
            }
            group.addTask { try? await Task.sleep(for: limit) }
            await group.next()
            group.cancelAll()
        }
    }
}
