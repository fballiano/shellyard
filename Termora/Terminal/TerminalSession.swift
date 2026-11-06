//
//  TerminalSession.swift
//  Termora
//

import Foundation
import GhosttyTerminal

/// What a pane runs.
struct TerminalLaunch: Equatable, Sendable {
    /// The command line to run. `nil` runs your login shell.
    var command: String?
    /// Extra environment variables for the child process.
    var environment: [String: String]
    var workingDirectory: String?
    /// Keep the pane open after the command exits, so you can read any error.
    var waitAfterCommand: Bool
    /// The name shown on the tab before the program sets a title.
    var title: String

    init(
        command: String? = nil,
        environment: [String: String] = [:],
        workingDirectory: String? = nil,
        waitAfterCommand: Bool = true,
        title: String = "Shell"
    ) {
        self.command = command
        self.environment = environment
        self.workingDirectory = workingDirectory
        self.waitAfterCommand = waitAfterCommand
        self.title = title
    }

    /// A local login shell, for a local tab.
    static var loginShell: TerminalLaunch {
        TerminalLaunch(waitAfterCommand: false, title: "Shell")
    }
}

/// One terminal pane.
///
/// This type is the only boundary between Termora and libghostty. Keep every
/// Ghostty call inside it, so that a change of terminal engine stays local.
@MainActor
final class TerminalSession: Identifiable, ObservableObject {
    let id: UUID
    let launch: TerminalLaunch
    let state: TerminalViewState

    /// The child process has exited.
    @Published private(set) var isFinished = false

    /// The one platform view of this pane, made the first time it is drawn.
    ///
    /// The Ghostty surface, and with it the process, belongs to this view. A
    /// split moves a pane to a new place in the SwiftUI tree, and closing one
    /// of two panes moves the other one up; SwiftUI then makes a new view
    /// there. A new view would start a new surface and a new process, and
    /// the old view would take the program you were running with it. Giving
    /// SwiftUI this view again moves it, surface and all.
    private var platformView: TerminalView?

    /// The owner sets this to remove the pane. The flag reports whether the
    /// child process was still running, so the owner can ask for confirmation.
    var onRequestClose: ((TerminalSession, _ processAlive: Bool) -> Void)?

    init(id: UUID = UUID(), launch: TerminalLaunch) {
        self.id = id
        self.launch = launch
        state = TerminalViewState(controller: GhosttyEnvironment.controller)
        state.configuration = TerminalSurfaceOptions(
            backend: .exec,
            workingDirectory: launch.workingDirectory,
            envVars: launch.environment,
            command: launch.command,
            waitAfterCommand: launch.waitAfterCommand,
            context: .window
        )
        state.makePlatformView = { [weak self] in
            if let view = self?.platformView { return view }
            let view = TerminalView(frame: .zero)
            self?.platformView = view
            return view
        }
        state.onClose = { [weak self] processAlive in
            MainActor.assumeIsolated {
                self?.handleClose(processAlive: processAlive)
            }
        }
    }

    /// The title to show on a tab. The program's own title wins when it sets one.
    var title: String {
        state.title.isEmpty ? launch.title : state.title
    }

    /// The folder the shell is in, as the shell reports it (OSC 7).
    ///
    /// A shell that reports nothing leaves this `nil`. A `file://` address
    /// becomes a plain path.
    var workingDirectory: String? {
        guard let reported = state.workingDirectory, !reported.isEmpty else { return nil }
        if reported.hasPrefix("file://"), let url = URL(string: reported) {
            return url.path
        }
        return reported
    }

    /// Waits until the shell in the pane looks ready for typing.
    ///
    /// libghostty tells nothing about output, but it does report the window
    /// title, and most shells set it as they draw the prompt: fish always,
    /// bash and zsh on most servers (their default files do it for any
    /// `xterm*` terminal). After the first change of title, a short pause
    /// lets the prompt finish. A shell that never sets a title gets
    /// `fallback`. Typing too early is not harmless: fish drops what arrives
    /// while it starts.
    func waitForPrompt(
        fallback: Duration = .seconds(3), settle: Duration = .milliseconds(300)
    ) async {
        let start = ContinuousClock.now
        let firstTitle = state.title
        while ContinuousClock.now - start < fallback, !isFinished {
            if state.title != firstTitle, !state.title.isEmpty {
                try? await Task.sleep(for: settle)
                return
            }
            try? await Task.sleep(for: .milliseconds(50))
        }
    }

    /// Stop drawing a pane that is hidden behind another tab. The grid, the
    /// scrollback, and the child process all stay alive.
    func setVisible(_ isVisible: Bool) {
        state.isSurfaceVisible = isVisible
    }

    func focus() {
        state.requestFocus()
    }

    /// Put text into the pane, as a paste.
    ///
    /// A program with bracketed paste on receives it as a paste, so a `\r`
    /// in the text lands in the edit line instead of running the line. Send
    /// the Enter key with `press(_:)` to run it.
    @discardableResult
    func send(_ text: String) -> Bool {
        state.paste(text: text)
    }

    /// Press one named key in the pane.
    ///
    /// Text goes through the paste path: a shell with bracketed paste on
    /// inserts a pasted `\r` instead of running the line. A key press is
    /// never framed as a paste.
    @discardableResult
    func press(_ key: TerminalKey) -> Bool {
        state.sendKey(key)
    }

    private func handleClose(processAlive: Bool) {
        isFinished = !processAlive
        onRequestClose?(self, processAlive)
    }
}
