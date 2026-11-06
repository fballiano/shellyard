//
//  SessionsController.swift
//  Termora
//

import Foundation
import GhosttyTerminal
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

    /// The remote files open in editors on this Mac. The controller outlives
    /// every browser view, because an editor stays open after its tab closes.
    let remoteEdits = RemoteEditController()

    private let store: DocumentStore
    private var engineStorage: SSHEngine?
    private var engineError: String?

    init(store: DocumentStore) {
        self.store = store
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
            switch tab.phase {
            case .ready: return .live
            case .connecting, .running: found = .connecting
            case .failed: break
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
                        port: connection.port,
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

            let target = SSHTarget(host: connection.host, port: connection.port, settings: settings)
            let sshConnection = await engine.connect(
                id: connection.id, name: connection.name, target: target
            )

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
                    let browser = FileBrowserModel(sshConnection: sshConnection)
                    browser.onEdit = { [weak self] entry, application in
                        self?.remoteEdits.edit(entry, on: sshConnection, with: application)
                    }
                    tab.browser = browser
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

    /// What `agentConnect` produced. A refusal carries the words the tool
    /// prints on standard error.
    enum AgentConnectOutcome {
        case success(SSHConnection)
        case failure(String)
    }

    /// Opens or reuses the control master for the `termora` tool, without a
    /// tab. When OpenSSH must ask, the askpass sheet appears here in the
    /// application, and the tool waits.
    func agentConnect(connection: Connection) async -> AgentConnectOutcome {
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
                    port: connection.port,
                    username: settings.username,
                    name: connection.name
                ),
                onOutput: { _ in }
            )
            if let problem = outcome.problem {
                return .failure("\(settings.beforeConnect.name): \(problem)")
            }
        }

        let target = SSHTarget(host: connection.host, port: connection.port, settings: settings)
        let sshConnection = await engine.connect(
            id: connection.id, name: connection.name, target: target
        )
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

    /// How long to let the far shell settle before typing into it.
    ///
    /// The pane opens before the prompt appears. Typing at once would send the
    /// text into a shell that is not listening yet.
    private static let settleBeforeTyping = Duration.milliseconds(700)

    /// Types the text a connection carries, once the session is open.
    private func typeAfterConnect(_ text: String, into session: TerminalSession) async {
        let steps = KeySequence.steps(from: text)
        guard !steps.isEmpty else { return }

        try? await Task.sleep(for: Self.settleBeforeTyping)
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
            // A pane whose program still runs is not closed on the spot: the
            // view asks first. A finished pane goes at once.
            if processAlive {
                self?.paneCloseRequest = PaneCloseRequest(paneID: session.id)
            } else {
                self?.close(paneID: session.id)
            }
        }
        return session
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

    func close(paneID: UUID) {
        guard let tab = tabs.first(where: { $0.panes.contains { $0.id == paneID } }) else { return }
        if tab.close(paneID: paneID) {
            closeTab(tab.id)
        }
        updateVisibility()
    }

    /// The bookmark a tab belongs to, if it is still in the document.
    func connection(of tab: TerminalTab) -> Connection? {
        tab.connectionID.flatMap { store.index.connection($0) }
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

    /// Closes every tab and every connection. The auto-lock calls this, so a
    /// locked document never leaves a live session behind it.
    func closeAllTabs() {
        for id in tabs.map(\.id) { closeTab(id) }
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
    /// and the process all stay alive.
    func updateVisibility() {
        for tab in tabs {
            let isVisible = tab.id == selectedTabID
            for pane in tab.panes { pane.setVisible(isVisible) }
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
