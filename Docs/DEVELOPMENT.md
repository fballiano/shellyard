# Developing Shellyard

This document is for people who change the code. For the use of the
application, see the [README](../README.md).

## The old name

Until version 1.2.0 the application was called Termora. Until version 1.4.0
the code, the bundle identifier, the settings keys, the folders, and the
document extension kept that name. Now everything says Shellyard.

Two places still know the old name, so that old data comes across:

- `LegacyMigration` runs once, at the first launch. It copies the settings of
  `com.fabrizioballiano.Termora` to the `Shellyard…` keys. It also renames the
  `Termora` folders in `~/Library/Application Support` and
  `~/Library/Caches`, when no `Shellyard` folder is there.
- `VaultFile` reads a document that starts with `TERMORA1`. Each save writes
  `SHELLYARD1`.

Shellyard opens only `.shellyard` documents. A person renames an old
`.termora` document in the Finder; the README tells how. A Touch ID record
belongs to the path of the document, so the person turns Touch ID on again
after the rename.

Do not remove the migration code. A person can update from any older
version.

## Requirements

- macOS 26 or later
- Xcode 26 or later
- XcodeGen (`brew install xcodegen`)

## Build

```sh
./run.sh              # make the project, build, and start the application
./run.sh --install    # also copy it to /Applications and link `shellyard`
```

`./run.sh` quits every running Shellyard before it starts the new build.

Or by hand:

```sh
xcodegen generate
xcodebuild -project Shellyard.xcodeproj -scheme Shellyard \
           -configuration Debug -derivedDataPath build build
open build/Build/Products/Debug/Shellyard.app
```

`Shellyard.xcodeproj` is generated. Do not edit it. Change `project.yml` and
run `xcodegen generate` again.

## Layout

| Path | Purpose |
|---|---|
| `Shellyard/Terminal` | The only code that calls libghostty |
| `Shellyard/Sessions` | Tabs, panes, and splits (`SessionsController`) |
| `Shellyard/UI` | Sidebar, tab bar, inspector, file browser |
| `Packages/ShellyardModel` | The object tree and folder inheritance |
| `Packages/ShellyardVault` | The encrypted document and the Touch ID key store |
| `Packages/ShellyardSSH` | The control master, the askpass service, and tunnels |
| `Packages/ShellyardImport` | The Royal TSX reader and the AppleScript bridge |
| `Packages/ShellyardSFTP` | The SFTP version 3 client and the file browser model |
| `ShellyardUITests` | Tests that drive the real application |
| `Tools/` | The `shellyard-askpass` helper and the `shellyard` command (`Tools/shellyard-cli`) |
| `Agents/`, `plugins/` | The agent integrations, one folder per agent |

A `TerminalTab` with no `connectionID` is a local shell tab.

## Tests

Each package is an independent SwiftPM package:

```sh
(cd Packages/ShellyardModel && swift test)
(cd Packages/ShellyardVault && swift test)
(cd Packages/ShellyardSSH && swift test)
(cd Packages/ShellyardSFTP && swift test)
(cd Packages/ShellyardImport && swift test)
```

The UI tests drive the real application:

```sh
xcodebuild -project Shellyard.xcodeproj -scheme Shellyard \
           -destination 'platform=macOS,arch=arm64' -derivedDataPath build test
```

They write a document with the vault API, then start the application with
`-ShellyardLastDocumentPath <path>`. `UserDefaults` reads `-key value` pairs
from the command line, so the application has no test-only code.

Some UI tests need a live connection. `Scripts/uitest-ssh.sh` starts an
OpenSSH server on a high port in a temporary folder and gives its port and
key to the tests. Without the script, those tests are skipped.

```sh
./Scripts/uitest-ssh.sh ShellyardUITests                     # every UI test
./Scripts/uitest-ssh.sh ShellyardUITests/TabShortcutsTests   # one class
```

The test of the folder sync needs an HTTP server, and the UI test runner may
not open a listening socket. `Scripts/uitest-sync.sh` builds
`Scripts/sync-test-server.swift`, starts it on a high port of `127.0.0.1`,
and runs `FolderSyncTests`. The server answers 401 without the right HTTP
Basic credentials. Without the script, the test is skipped.

```sh
./Scripts/uitest-sync.sh
```

The SSH package tests start their own OpenSSH server on a high port, in its
own folder, and build `shellyard-askpass` from source. They read and write
nothing in your `~/.ssh`. They are skipped when `/usr/sbin/sshd` is missing.

The SFTP tests talk to `/usr/libexec/sftp-server`, which macOS ships. It is
the program that OpenSSH runs for the `sftp` subsystem, so the protocol is
real, with no network and no keys. Each test works in its own temporary
folder and removes it after.

Two suites are opt-in:

- `SHELLYARD_ROYAL_DOCUMENT=<path>` runs the import tests against a real
  Royal TSX document. They only read it, and they check counts and shapes:
  no host name, no user name, and no secret is printed.
- `SHELLYARD_TEST_ROYAL_BRIDGE=1 swift test --filter RoyalBridgeLiveTests`, in
  `Packages/ShellyardImport`, starts the real Royal TSX application.

## Release

1. Raise `MARKETING_VERSION` in `project.yml`, and commit.
2. Push `main`, then push a tag `v<version>`.

The tag starts `.github/workflows/release.yml`. It builds the Release
configuration, signs it with the Developer ID certificate, has Apple notarize
it, staples the ticket, publishes a GitHub release with the zip, and points
`Casks/shellyard.rb` in
[fballiano/homebrew-tap](https://github.com/fballiano/homebrew-tap) at the
new zip. It pushes to the tap with the deploy key in the secret
`TAP_DEPLOY_KEY`, which can write to that repository only.

Until 1.2.0, this repository was its own tap, `fballiano/termora`. It has no
cask now. A user of the old tap moves with the commands in the README.

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
`Scripts/setup-signing.sh` in a terminal of its own: it walks you through
the certificate, the App Store Connect API key, and `gh`, and it writes
nothing to disk. It makes the certificate on the developer website, because
Xcode refuses unless it is signed in with the Account Holder's Apple ID.

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

Shellyard never speaks the SSH protocol. It drives `/usr/bin/ssh`, so it
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

### Masters that outlive Shellyard

A master is a process of its own, so it can outlive the application. Shellyard
closes every master on each lock and on each quit, also the masters of
`shellyard run`, which have no tab. Every lock path goes through
`DocumentStore.willClose`, which calls `SessionsController.closeEverything()`.

A crash or Force Quit gives Shellyard no chance to close anything. The masters
then run on under launchd, with their connections and tunnels, and a master
that died leaves its socket file, which stops a new master from binding that
path. At launch, `SSHEngine.clearLeftoverMasters()` looks at every
`tc-*.sock` in the control folder:

- No master answers `ssh -O check`: the file is removed.
- The master is `ssh` and its parent is launchd (PID 1): it gets `-O exit`.
- The master has a live parent: it belongs to a copy of Shellyard that runs
  now, and it is left alone.

The first connect waits for this work to end.

### When the master stops

`SSHConnection.onLost` fires when the master exits while it was connected
and Shellyard did not close it. The panes and channels on the master stop with
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

Shellyard puts the description on the server one time, as soon as the master
is up:

```
infocmp -x xterm-ghostty                     from the description inside Shellyard
ssh -S <socket> <host> sh -c '…tic -x -o "$HOME/.terminfo" -…'
```

The work uses the control master, so nobody is asked for a password again. It
writes one file, `~/.terminfo/78/xterm-ghostty`. A record in
`~/Library/Caches/Shellyard/terminfo.json` stops Shellyard from doing it twice;
a new version of the description replaces the old one.

A server with no `tic`, or with a read-only home folder, is left alone. The
pane then announces `xterm-256color`. Every pane runs
`/usr/bin/env TERM=<name> /usr/bin/ssh …`, and the name is the one that the
server proved it understands.

### How a password reaches OpenSSH

A secret never appears in a command line, in the environment, or in a file.
Shellyard sets `SSH_ASKPASS` to `shellyard-askpass` and `SSH_ASKPASS_REQUIRE` to
`force`, which sends every question to the helper, also when a terminal is
present. The helper holds no secret: it gives the prompt to Shellyard over a
Unix socket in a private folder, with a random token for that one connection
attempt, and prints the answer it receives.

`Tools/shellyard-askpass/main.swift` and
`Packages/ShellyardSSH/Sources/ShellyardSSH/AskpassClient.swift` are compiled into
both the helper and the library, so the tool and the tests always speak the
same version of the protocol.

## The document format

```
"SHELLYARD1"      10 bytes ("TERMORA1", 8 bytes, in an old document)
header length     4 bytes, big-endian
header            JSON: format version, cipher, key derivation parameters
body              AES-256-GCM: nonce, ciphertext, tag
```

The header stays readable so that Shellyard can find the key derivation
parameters before it asks for a password. Everything else, including every
host name, is inside the sealed body. The header is the additional
authenticated data, so a change to the salt or to the round count breaks the
seal.

The master password becomes the key through PBKDF2-HMAC-SHA512 with 600,000
rounds, which takes about 0.44 seconds on Apple silicon.

A synced document can meet an older Shellyard on another Mac, so a change to
the JSON must stay readable there. A version older than 1.4.0 cannot read a
document that starts with `SHELLYARD1`; that break came with the rename and
is the only one. Shellyard 1.0 requires every field of a
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
   Mac, so Shellyard keeps it in a plain file.
2. Shellyard makes a second key pair, agrees a shared secret with the Secure
   Enclave public key through ECDH, and drops its own private half.
3. The document key is sealed with a key derived from that secret (HKDF over
   the document salt).

Only the Secure Enclave can agree the secret again, and it asks for Touch ID
first. Records live in `~/Library/Application Support/Shellyard/TouchID`, one
file per document and salt, mode 0600.

When Shellyard cannot remember a key, it tells the person. A quiet failure looks
the same as success until the next launch asks for the password again.

## The file browser

Shellyard speaks SFTP version 3 itself, on the channel that `ssh … -s sftp`
opens. There is no second process, no second password, and no cryptography
in Shellyard.

A folder copy counts the whole tree first, so one progress bar runs from start
to end. A symbolic link is left out, not followed.

Nothing is copied while you drag to Finder. Finder receives one file promise
per row and asks for each item only when you release the pointer. The list
is an `NSTableView`, not a SwiftUI `Table`, for that one reason: only AppKit
can give Finder an `NSFilePromiseProvider` for every selected row. See
`Shellyard/UI/RemoteFileTable.swift`. The decisions that each promise needs
live in `SFTPPromise`, apart from AppKit, so they can be tested.

## The Royal TSX import

A Royal document is a flat list of typed objects joined by `ParentID`, and
the importer keeps that shape, so folder inheritance survives.

### Passwords through AppleScript

Royal TSX encrypts `CredentialPassword` and `CredentialPassphrase` with a
scheme it does not publish. Shellyard does not guess at it. Royal TSX has an
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
- Shellyard does not call a shell. `LocalCommandRunner.arguments(from:)` splits
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

## The export and the import

The export writes a JSON file in the public format that
[CONNECTIONS-FORMAT.md](CONNECTIONS-FORMAT.md) specifies. The import reads the
same file. The format is not the internal document JSON: that JSON is a flat
list joined by `parentID`, and it carries fields for old versions.

- `ConnectionsFile` (ShellyardModel) reads and writes the format. A bad item
  becomes `.invalid` and does not stop the read. A failed `decode` in an
  unkeyed container does not move to the next element, so `LossyItem`
  catches the error inside.
- `ConnectionsFile(exporting:from:includeSecrets:)` makes the file. A branch
  loses the folders above it, so the top node of the branch gets the values
  that it inherits (`DocumentIndex.settingsWithInheritedValues`).
- `ConnectionsImport` is the plan that the import sheet shows as a preview.
  It gives every node a new identifier. It removes each command before
  connecting, unless the person keeps them, and always removes a command
  with a password mark.
- `ConnectionsFileStorage.write` makes the file with mode 0600, then renames
  it over the target. `FileManager.replaceItemAt` is not used, because it
  keeps the permissions of the file that it replaces.

## Synced folders

A folder with a `FolderSync` gets its contents from a web address that
returns a connections file. `SyncController` (in the app) fetches the file
and runs the schedule. `Document.applySync` (in ShellyardModel, with
`SyncEngineTests`) changes the document.

- **Identity.** Each node that a sync makes has a `SyncLink`: the synced
  folder and the `id` of the item. A node without a link belongs to the
  person, and the sync never touches it.
- **Local changes stay.** The link also holds `base`, the values that the
  file gave the last time. A field whose value is still `base` was not
  changed here, so it takes the new value. Any other field keeps the local
  value. The password merges apart from the method, so a password typed
  here survives a file that sends none.
- **The settings of the list.** The top-level `settings` of the file merge
  into the synced folder itself, the same way. Their base is
  `FolderSync.settingsBase`. A setting that the person set before the first
  sync stays, because the first base is "inherit all".
- **Deleted stays deleted.** A delete records the `id` in
  `FolderSync.excludedIDs`. A synced node found outside its folder was moved
  out by the person: it loses its link, and its `id` is excluded too. A node
  whose parent no longer exists is not "outside": the sync places it again.
  The children of an excluded folder are still read, and take its place.
- **Order.** Synced nodes take the order of the file. Before the sync,
  `rememberLocalPlaces` notes the synced nodes above each node of the
  person. After it, that node goes below the nearest of them that is still
  in the same folder, or to the top when there is none. A node that is new
  in the folder goes to the end.
- **Detached nodes.** `releaseDetachedSyncedNodes` runs after each
  `DocumentStore.update` and when a document opens. It clears the link of a
  node that is outside its synced folder (and excludes its `id`), and of a
  node whose synced folder is gone or has its sync off. Without it, a synced
  folder that the person moved out, and whose synced folder they then
  deleted, kept a dead link: no sync cleared it, and the inspector hid its
  Sync section.
- **A secret stays with its method.** A password typed here never becomes the
  passphrase of a key that the file sends, or the other way round.
- **Trust.** Unless `trustsServer` is on, the engine removes commands before
  connecting, agent forwarding, and X11 forwarding from the file.
- **Sync off.** When the person turns the sync off, `releaseSyncedNodes`
  clears the links, so a later sync from another address removes nothing.
- **The editor.** The editor sheet keeps a draft and the stored value it
  started from (`base`). A save writes only the fields that the draft
  changed (`applyingEdits(of:since:)`), never the place or the link. A sync
  that runs while the editor is open is therefore not undone.
- **Safety.** The engine works on a copy and throws without a change when
  the file has no usable item and the folder has synced nodes. While the
  file has a bad item, nothing is removed.
- **The request.** HTTPS only, or HTTP to `localhost` (`NSAllowsLocalNetworking`
  in Info.plist). An ephemeral session, HTTP Basic, a 20 MB limit checked
  during the download, and redirects to the same origin only.
- **The schedule.** The controller checks every 15 minutes and when the
  document opens. It skips while an editor is open, because the draft of the
  editor would write old values over the result. The status of the last
  sync stays in `UserDefaults` (`ShellyardSyncStatus`), not in the document.
- **Compatibility.** A version older than 2.0.0 drops `sync` and `syncLink`
  when it saves the document.

## The terminal engine

### The theme

libghostty reads your own `config` file, but it cannot resolve a
`theme = <name>` line: Ghostty loads theme files from its own application
bundle, and Shellyard is a different bundle. `GhosttyConfigFile.themeChoice(in:)`
reads that line, and `GhosttyEnvironment.userTheme()` finds the theme in the
catalogue that ships with `libghostty-spm`.

Do not pass an empty `TerminalTheme()`: the package then puts its own colours
over everything, and a pane looks nothing like your Ghostty window.

### The upstream libghostty-spm

Shellyard depends on `Lakr233/libghostty-spm`, pinned to an exact version in
`project.yml`. It is the only remote dependency, and Shellyard always pins the
newest upstream release. Shellyard once carried a vendored copy with three
fixes; all three are upstream since 1.4.5: the wakeup observers,
`TerminalViewState.isSurfaceVisible`, and programmatic key presses through
`ghostty_surface_key`. Before you pin a newer version, make sure that the
three are still there. Each one prevents a bug that Shellyard hit.

Since 2.2.2026111302, `TerminalViewState.onOpenURL` is also upstream.
Shellyard sets it in `TerminalSession`. On macOS, Ghostty's own opener
refuses every link in the terminal: an OSC 8 hyperlink, and a URL that it
finds in the text too. Without the hook, a ⌘-click on a link does nothing.
The hook opens only `http`, `https`, and `mailto` links
(`TerminalSession.linkSchemes`), because the program in the pane sets the
target. Make sure that the hook is still there before you pin a newer version.

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
Adding `ShellyardSSH` to `ShellyardUITests` stopped the application under test
from opening any window, with no error. The test bundle links only the
packages it imports itself.

**OpenSSH ends its lines with CR LF, and Swift counts that pair as one
`Character`.** `split(separator: "\n")` finds nothing and returns the whole
log as one line. Use `split(whereSeparator: \.isNewline)`. See
`CommandResult.lines(of:)`.

**Swift 6.3.3 crashes in code generation** when a method reference goes
straight to a `Binding` setter, as in `set: change`. Write the closure out:
`set: { newValue in change(to: newValue) }`. See `AuthenticationEditor` in
`Shellyard/UI/InspectorView.swift`.

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
text after connecting, which Shellyard pastes.

**In a UI test, an identifier query can count more than one element per
view.** Compare a count with the count before the action, not with a fixed
number.

## The application icon

The icon is the Tabler `terminal` icon on the macOS rounded square.
`Tools/make-app-icon.swift` draws it with CoreGraphics and writes every size:

    swift Tools/make-app-icon.swift Shellyard/Resources/Assets.xcassets/AppIcon.appiconset

ImageMagick cannot render the source SVG: its built-in renderer drops strokes
and gradients.
