# Developing Termora

This document is for people who change the code. For the use of the
application, see the [README](../README.md).

## Requirements

- macOS 26 or later
- Xcode 26 or later
- XcodeGen (`brew install xcodegen`)

## Build

```sh
./run.sh              # make the project, build, and start the application
./run.sh --install    # also copy it to /Applications and link `termora`
```

`./run.sh` quits every running Termora before it starts the new build.

Or by hand:

```sh
xcodegen generate
xcodebuild -project Termora.xcodeproj -scheme Termora \
           -configuration Debug -derivedDataPath build build
open build/Build/Products/Debug/Termora.app
```

`Termora.xcodeproj` is generated. Do not edit it. Change `project.yml` and
run `xcodegen generate` again.

## Layout

| Path | Purpose |
|---|---|
| `Termora/Terminal` | The only code that calls libghostty |
| `Termora/Sessions` | Tabs, panes, and splits (`SessionsController`) |
| `Termora/UI` | Sidebar, tab bar, inspector, file browser |
| `Packages/TermoraModel` | The object tree and folder inheritance |
| `Packages/TermoraVault` | The encrypted document and the Touch ID key store |
| `Packages/TermoraSSH` | The control master, the askpass service, and tunnels |
| `Packages/TermoraImport` | The Royal TSX reader and the AppleScript bridge |
| `Packages/TermoraSFTP` | The SFTP version 3 client and the file browser model |
| `TermoraUITests` | Tests that drive the real application |
| `Tools/` | The `termora-askpass` helper and the `termora` command |
| `Agents/`, `plugins/` | The agent integrations, one folder per agent |

A `TerminalTab` with no `connectionID` is a local shell tab.

## Tests

Each package is an independent SwiftPM package:

```sh
(cd Packages/TermoraModel && swift test)
(cd Packages/TermoraVault && swift test)
(cd Packages/TermoraSSH && swift test)
(cd Packages/TermoraSFTP && swift test)
(cd Packages/TermoraImport && swift test)
```

The UI tests drive the real application:

```sh
xcodebuild -project Termora.xcodeproj -scheme Termora \
           -destination 'platform=macOS,arch=arm64' -derivedDataPath build test
```

They write a document with the vault API, then start the application with
`-TermoraLastDocumentPath <path>`. `UserDefaults` reads `-key value` pairs
from the command line, so the application has no test-only code.

Some UI tests need a live connection. `Scripts/uitest-ssh.sh` starts an
OpenSSH server on a high port in a temporary folder and gives its port and
key to the tests. Without the script, those tests are skipped.

```sh
./Scripts/uitest-ssh.sh TermoraUITests                     # every UI test
./Scripts/uitest-ssh.sh TermoraUITests/TabShortcutsTests   # one class
```

The SSH package tests start their own OpenSSH server on a high port, in its
own folder, and build `termora-askpass` from source. They read and write
nothing in your `~/.ssh`. They are skipped when `/usr/sbin/sshd` is missing.

The SFTP tests talk to `/usr/libexec/sftp-server`, which macOS ships. It is
the program that OpenSSH runs for the `sftp` subsystem, so the protocol is
real, with no network and no keys. Each test works in its own temporary
folder and removes it after.

Two suites are opt-in:

- `TERMORA_ROYAL_DOCUMENT=<path>` runs the import tests against a real
  Royal TSX document. They only read it, and they check counts and shapes:
  no host name, no user name, and no secret is printed.
- `TERMORA_TEST_ROYAL_BRIDGE=1 swift test --filter RoyalBridgeLiveTests`, in
  `Packages/TermoraImport`, starts the real Royal TSX application.

## Release

1. Raise `MARKETING_VERSION` in `project.yml`, and commit.
2. Push `main`, then push a tag `v<version>`.

The tag starts `.github/workflows/release.yml`. It builds the Release
configuration, signs it with the Developer ID certificate, has Apple notarize
it, staples the ticket, publishes a GitHub release with the zip, and points
`Casks/termora.rb` at the new zip with a commit on `main`. Pull that commit
before your next push.

### Signing and notarization

Local builds stay ad hoc: `project.yml` signs with `-`, so `./run.sh` and the
tests need no certificate. Only the workflow signs with Developer ID, through
settings on the `xcodebuild` command line, which reach every target: the app
and the two tools inside it get the same signature, the hardened runtime, and
a secure timestamp. `CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO` keeps
`get-task-allow` out, which notarization refuses.

Before it asks Apple, the workflow checks each executable for the team, the
hardened runtime, the timestamp, and no `get-task-allow`, and it starts both
tools once: a restricted entitlement with no provisioning profile gets a
program killed at launch, and nobody would see it in a tool.

The workflow needs one repository variable and five secrets. Run
`Scripts/setup-signing.sh`: it walks you through the certificate, the
App Store Connect API key, and `gh`, and it writes nothing to disk.

| Name | Kind | What it is |
| --- | --- | --- |
| `APPLE_TEAM_ID` | variable | The Team ID, `H95XQBELRP` |
| `DEVELOPER_ID_P12_BASE64` | secret | The Developer ID Application certificate with its key |
| `DEVELOPER_ID_P12_PASSWORD` | secret | The password of that `.p12` |
| `NOTARY_KEY_P8_BASE64` | secret | An App Store Connect API key (Developer role) |
| `NOTARY_KEY_ID` | secret | The ID of that key |
| `NOTARY_ISSUER_ID` | secret | Its issuer ID |

**Actions → Release → Run workflow** is a dry run: it signs and notarizes,
keeps the zip as an artifact, and publishes nothing. Run it after a change to
the signing.

## How a connection works

Termora never speaks the SSH protocol. It drives `/usr/bin/ssh`, so it
inherits `~/.ssh/config`, certificates, FIDO keys, agent support, and
`known_hosts`.

One control master carries the whole connection:

```
ssh -M -N -T -S <socket> …                          authenticates once
ssh -S <socket> -o ControlMaster=no <host>          a terminal pane
ssh -S <socket> -o ControlMaster=no <host> -s sftp  the SFTP channel
ssh -S <socket> -O forward -L …                     a tunnel, added while connected
ssh -S <socket> -O exit                             closes everything
```

The master is separate from every pane, so you can close all the panes and
keep the connection and its tunnels alive. A second tab on a live master
does not run the command before connecting again and does not open the
tunnels again.

### Masters that outlive Termora

A master is a process of its own, so it can outlive the application. Termora
closes every master on each lock and on each quit, also the masters of
`termora run`, which have no tab. Every lock path goes through
`DocumentStore.willClose`, which calls `SessionsController.closeEverything()`.

A crash or Force Quit gives Termora no chance to close anything. The masters
then run on under launchd, with their connections and tunnels, and a master
that died leaves its socket file, which stops a new master from binding that
path. At launch, `SSHEngine.clearLeftoverMasters()` looks at every
`tc-*.sock` in the control folder:

- No master answers `ssh -O check`: the file is removed.
- The master is `ssh` and its parent is launchd (PID 1): it gets `-O exit`.
- The master has a live parent: it belongs to a copy of Termora that runs
  now, and it is left alone.

The first connect waits for this work to end.

### When the master stops

`SSHConnection.onLost` fires when the master exits while it was connected
and Termora did not close it. The panes and channels on the master stop with
it. `SessionsController` sets `lostReason` on every tab of that connection;
the phase stays `ready`, so the panes stay in the view tree, and the bar is an
overlay. Ghostty asks to close a finished pane on any key press, and the
controller ignores that request while `lostReason` is set.

Reconnect drops the dead master, opens a new one with `establish`, and puts a
new session in the place of each pane with `PaneNode.replacePanes`. Each new
pane gets its own `TerminalSurfaceView` (`.id(session.id)`), because a
surface cannot take a second session. A new tab may already have opened a
live master (⌘T on a lost tab); Reconnect then uses it.

After a sleep, `SessionsController` waits for a network path (up to 30
seconds), runs `true` over each live master with a 10-second limit, drops
the masters that fail, and reconnects every lost tab. A master runs on this
Mac, so only a round trip to the server shows that it still works. No UI
test can put the Mac to sleep, so this path has no automated test.

The package test drops the connection from the server side.
`TestSSHServer.dropConnections()` kills the whole process tree under the
listener: killing only `sshd-session [postauth]` moves its worker to
launchd, and the connection lives on. `ReconnectTests` in the UI tests drops
it from inside the remote shell.

### The terminal the server sees

Ghostty calls itself `xterm-ghostty`. OpenSSH copies `TERM` into the request
for the remote terminal, and almost no server has that description.

Termora puts the description on the server one time, as soon as the master
is up:

```
infocmp -x xterm-ghostty                     from the description inside Termora
ssh -S <socket> <host> sh -c '…tic -x -o "$HOME/.terminfo" -…'
```

The work uses the control master, so nobody is asked for a password again. It
writes one file, `~/.terminfo/78/xterm-ghostty`. A record in
`~/Library/Caches/Termora/terminfo.json` stops Termora from doing it twice;
a new version of the description replaces the old one.

A server with no `tic`, or with a read-only home folder, is left alone. The
pane then announces `xterm-256color`. Every pane runs
`/usr/bin/env TERM=<name> /usr/bin/ssh …`, and the name is the one that the
server proved it understands.

### How a password reaches OpenSSH

A secret never appears in a command line, in the environment, or in a file.
Termora sets `SSH_ASKPASS` to `termora-askpass` and `SSH_ASKPASS_REQUIRE` to
`force`, which sends every question to the helper, also when a terminal is
present. The helper holds no secret: it gives the prompt to Termora over a
Unix socket in a private folder, with a random token for that one connection
attempt, and prints the answer it receives.

`Tools/termora-askpass/main.swift` and
`Packages/TermoraSSH/Sources/TermoraSSH/AskpassClient.swift` are compiled into
both the helper and the library, so the tool and the tests always speak the
same version of the protocol.

## The document format

```
"TERMORA1"        8 bytes
header length     4 bytes, big-endian
header            JSON: format version, cipher, key derivation parameters
body              AES-256-GCM: nonce, ciphertext, tag
```

The header stays readable so that Termora can find the key derivation
parameters before it asks for a password. Everything else, including every
host name, is inside the sealed body. The header is the additional
authenticated data, so a change to the salt or to the round count breaks the
seal.

The master password becomes the key through PBKDF2-HMAC-SHA512 with 600,000
rounds, which takes about 0.44 seconds on Apple silicon.

A synced document can meet an older Termora on another Mac, so a change to
the JSON must stay readable there. Termora 1.0 requires every field of a
connection. A port that is not set is therefore written as `"port": 22`
with `"portFromSSHConfig": true` beside it: 1.0 ignores the flag and uses
22. `DocumentTests` decodes the new JSON with the 1.0 shape to prove it.

### Touch ID without a signing identity

A Keychain item that Touch ID guards needs the `keychain-access-groups`
entitlement. macOS accepts that entitlement only from a build signed with a
real team identity. With an ad-hoc signature every such call returns
`errSecMissingEntitlement` (-34018), and a signed entitlement makes macOS stop
the process at launch (exit 137). Both were measured.

`VaultKeyStore` therefore does not use the Keychain. It uses the Secure
Enclave, which has no such rule:

1. The Secure Enclave makes a private key guarded by `.biometryCurrentSet`.
   Its `dataRepresentation` is a sealed record that is useless on a different
   Mac, so Termora keeps it in a plain file.
2. Termora makes a second key pair, agrees a shared secret with the Secure
   Enclave public key through ECDH, and drops its own private half.
3. The document key is sealed with a key derived from that secret (HKDF over
   the document salt).

Only the Secure Enclave can agree the secret again, and it asks for Touch ID
first. Records live in `~/Library/Application Support/Termora/TouchID`, one
file per document and salt, mode 0600.

When Termora cannot remember a key, it tells the person. A quiet failure looks
the same as success until the next launch asks for the password again.

## The file browser

Termora speaks SFTP version 3 itself, on the channel that `ssh … -s sftp`
opens. There is no second process, no second password, and no cryptography
in Termora.

A folder copy counts the whole tree first, so one progress bar runs from start
to end. A symbolic link is left out, not followed.

Nothing is copied while you drag to Finder. Finder receives one file promise
per row and asks for each item only when you release the pointer. The list
is an `NSTableView`, not a SwiftUI `Table`, for that one reason: only AppKit
can give Finder an `NSFilePromiseProvider` for every selected row. See
`Termora/UI/RemoteFileTable.swift`. The decisions that each promise needs
live in `SFTPPromise`, apart from AppKit, so they can be tested.

## The Royal TSX import

A Royal document is a flat list of typed objects joined by `ParentID`, and
the importer keeps that shape, so folder inheritance survives.

### Passwords through AppleScript

Royal TSX encrypts `CredentialPassword` and `CredentialPassphrase` with a
scheme it does not publish. Termora does not guess at it. Royal TSX has an
AppleScript command, `get property value`, that returns the decrypted value.
Against a real document, Royal TSX gave all 12 stored secrets.

Royal TSX needs about two seconds after it opens a document before it
answers. `RoyalTSXBridge.openDocument(path:)` waits inside the script, so the
application is idle during that time.

`RoyalTSXBridge` is bound to the main actor. `NSAppleScript` needs the main
thread and a run loop: called from a different thread it does not fail, it
never returns. The binding turns that hang into a compiler error.

### Tasks

A connections document holds only the name or the identifier of a task. The
commands live in
`~/Library/Application Support/Royal TSX/UserPreferences.config`, which is the
same `RTSZDocument` XML, so `RoyalDocumentParser` reads it as it is.
`RoyalTaskLibrary` picks the `RoyalCommandTask` objects out of it, and the
importer joins them to `PreConnectTaskName` and `PreConnectTaskId`.

A task becomes `NodeSettings.beforeConnect`. It is inheritable, so a task on
a Royal folder still reaches every connection in that folder. Two rules:

- A task that puts `$PASSWORD$` on its command line is refused.
- Termora does not call a shell. `LocalCommandRunner.arguments(from:)` splits
  the argument line itself, so a mark such as `;` in a host name stays one
  word.

### A task runs with the PATH of a login shell

An application started from the Dock gets the small `PATH` that `launchd`
sets, usually `/usr/bin:/bin:/usr/sbin:/sbin`. A Royal task expects the
`PATH` of a terminal. `LocalCommandRunner.loginPath` asks
`$SHELL -lc 'printf %s "$PATH"'` one time, with a fixed command that carries
no value from any document.

`programPath(for:searching:)` then finds a program named without a path, the
way a shell does. Royal's own `Ping` task names `ping`, which is in `/sbin` on
a Mac.

## The terminal engine

### The theme

libghostty reads your own `config` file, but it cannot resolve a
`theme = <name>` line: Ghostty loads theme files from its own application
bundle, and Termora is a different bundle. `GhosttyConfigFile.themeChoice(in:)`
reads that line, and `GhosttyEnvironment.userTheme()` finds the theme in the
catalogue that ships with `libghostty-spm`.

Do not pass an empty `TerminalTheme()`: the package then puts its own colours
over everything, and a pane looks nothing like your Ghostty window.

### The upstream libghostty-spm

Termora depends on `Lakr233/libghostty-spm`, pinned to an exact version in
`project.yml`. It is the only remote dependency, and Termora always pins the
newest upstream release. Termora once carried a vendored copy with three
fixes; all three are upstream since 1.4.5: the wakeup observers,
`TerminalViewState.isSurfaceVisible`, and programmatic key presses through
`ghostty_surface_key`. Before you pin a newer version, make sure that the
three are still there. Each one prevents a bug that Termora hit.

## Traps

**Never take a terminal tab out of the view tree.** The tab area draws every
tab in a `ZStack` and makes the hidden ones clear with `opacity(0)`. This
form is wrong:

    if let tab = sessions.selectedTab { TabContent(tab: tab).id(tab.id) }   // WRONG

It removes the previous tab from the view tree, which ends its
`TerminalSurfaceView`. libghostty cannot give the same terminal a second
surface, so the tab stays blank forever. `SessionsController.updateVisibility()`
sets `isSurfaceVisible` so that libghostty stops drawing a hidden tab: stop
the drawing, keep the view.

**A new menu shortcut must also go in `GhosttyEnvironment.menuKeyTriggers`.**
A focused pane takes every key that Ghostty binds (⌘T is `new_tab`), and the
menu never sees it.

**Do not use `.searchable` in the sidebar.** With `placement: .sidebar` the
system draws its field above all other sidebar content, so nothing can sit
above the filter. `SidebarView` has its own `FilterField`.

**A UI test target must not link a package that the application links.**
Adding `TermoraSSH` to `TermoraUITests` stopped the application under test
from opening any window, with no error. The test bundle links only the
packages it imports itself.

**OpenSSH ends its lines with CR LF, and Swift counts that pair as one
`Character`.** `split(separator: "\n")` finds nothing and returns the whole
log as one line. Use `split(whereSeparator: \.isNewline)`. See
`CommandResult.lines(of:)`.

**Swift 6.3.3 crashes in code generation** when a method reference goes
straight to a `Binding` setter, as in `set: change`. Write the closure out:
`set: { newValue in change(to: newValue) }`. See `AuthenticationEditor` in
`Termora/UI/InspectorView.swift`.

**Each pane keeps its one `TerminalView`.** The Ghostty surface, and so the
process, belongs to the platform view. A split moves a pane to a new place
in the SwiftUI tree, and closing one of two panes moves the other one up;
SwiftUI then makes a new view there, which started a new shell and ended
the program in the pane. `TerminalSession` gives SwiftUI the same view again
through `TerminalViewState.makePlatformView`, so the view moves with its
surface. `LocalTabTests.testSplitKeepsTheRunningProgram` guards it.

**After connecting waits for the window title.** libghostty reports no
output, but it reports the title, and most shells set it as they draw the
prompt. fish drops input that arrives while it starts, so a fixed wait was
too short. See `TerminalSession.waitForPrompt()`.

**XCUITest finds no hit point inside the tab strip in the title bar.**
`click()` on a tab fails with "Unable to find hit point for ScrollView".
Click the tab name by its coordinates:
`element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()`.

**XCUITest `typeText` can drop characters that need Shift**, such as `:`,
with some keyboard layouts. Put such text in the fixture, for example as the
text after connecting, which Termora pastes.

**In a UI test, an identifier query can count more than one element per
view.** Compare a count with the count before the action, not with a fixed
number.

## The application icon

The icon is the Tabler `terminal` icon on the macOS rounded square.
`Tools/make-app-icon.swift` draws it with CoreGraphics and writes every size:

    swift Tools/make-app-icon.swift Termora/Resources/Assets.xcassets/AppIcon.appiconset

ImageMagick cannot render the source SVG: its built-in renderer drops strokes
and gradients.
