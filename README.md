<div align="center">
<img src="Docs/icon.png" width="128" alt="Termora" />
<h1>Termora</h1>
<p><strong>SSH connections, tunnels and files in one encrypted document.</strong></p>
<p>
<a href="https://github.com/fballiano/termora/releases/latest"><img src="https://img.shields.io/github/v/release/fballiano/termora?style=for-the-badge&color=1E8A5F&labelColor=1B1F23" alt="Latest release" /></a>
<a href="https://github.com/fballiano/termora/releases"><img src="https://img.shields.io/github/downloads/fballiano/termora/total?style=for-the-badge&color=1E8A5F&labelColor=1B1F23" alt="Downloads" /></a>
<img src="https://img.shields.io/badge/macOS-26%2B-1E8A5F?style=for-the-badge&labelColor=1B1F23&logo=apple&logoColor=white" alt="macOS 26 or later" />
<a href="LICENSE"><img src="https://img.shields.io/badge/licence-MIT-1E8A5F?style=for-the-badge&labelColor=1B1F23" alt="MIT licence" /></a>
</p>
<p><a href="https://github.com/fballiano/termora/releases/latest"><img src="https://img.shields.io/badge/Download%20for%20macOS-1E8A5F?style=for-the-badge&labelColor=1E8A5F&logo=data:image/svg%2Bxml;base64,PHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHZpZXdCb3g9IjAgMCAyNCAyNCIgZmlsbD0ibm9uZSIgc3Ryb2tlPSIjZmZmIiBzdHJva2Utd2lkdGg9IjIiIHN0cm9rZS1saW5lY2FwPSJyb3VuZCIgc3Ryb2tlLWxpbmVqb2luPSJyb3VuZCI+PHBhdGggZD0iTTQgMTd2MmEyIDIgMCAwIDAgMiAyaDEyYTIgMiAwIDAgMCAyIC0ydi0yIi8+PHBhdGggZD0iTTcgMTFsNSA1bDUgLTUiLz48cGF0aCBkPSJNMTIgNGwwIDEyIi8+PC9zdmc+" alt="Download for macOS" height="36" /></a></p>
</div>

<table align=center><tr><td align=center>
<strong>If you find my work valuable, please consider sponsoring</strong><br />
<a href="https://github.com/sponsors/fballiano" target=_blank title="Sponsor me on GitHub"><img src="https://img.shields.io/badge/sponsor-30363D?style=for-the-badge&logo=GitHub-Sponsors&logoColor=#white" alt="Sponsor me on GitHub" /></a>
<a href="https://www.buymeacoffee.com/fballiano" target=_blank title="Buy me a coffee"><img src="https://img.shields.io/badge/Buy_Me_A_Coffee-FFDD00?style=for-the-badge&logo=buy-me-a-coffee&logoColor=black" alt="Buy me a coffee" /></a>
<a href="https://www.paypal.com/paypalme/fabrizioballiano" target=_blank title="Donate via PayPal"><img src="https://img.shields.io/badge/PayPal-00457C?style=for-the-badge&logo=paypal&logoColor=white" alt="Donate via PayPal" /></a>
</td></tr></table>

---

Termora is an SSH connection manager for macOS. It keeps your servers, their
passwords, and their tunnels in one encrypted file, and it opens them in the
Ghostty terminal engine. It also opens a shell on your Mac, so one window
holds all of your terminal work.

Termora drives the OpenSSH of macOS. Your `~/.ssh/config`, your keys, and
your SSH agent all work as they stand.

## Features

<table>
<tr><td><b>A bookmark tree</b></td><td>Folders pass credentials and settings down. A connection overrides only what it sets.</td></tr>
<tr><td><b>Your terminal</b></td><td>The Ghostty engine reads your own Ghostty configuration, so a pane looks like your terminal.</td></tr>
<tr><td><b>Local shells</b></td><td>A shell on this Mac, beside your servers, so you do not switch to another terminal.</td></tr>
<tr><td><b>Tabs and splits</b></td><td>Tabs live in the title bar. ⌘T opens a tab like the one in front, ⌘D and ⇧⌘D split.</td></tr>
<tr><td><b>One connection</b></td><td>One control master carries every pane, every tunnel and the file browser. Nothing authenticates twice.</td></tr>
<tr><td><b>htop just works</b></td><td>Termora teaches each server what <code>xterm-ghostty</code> is, once. A server that refuses gets <code>xterm-256color</code>.</td></tr>
<tr><td><b>Live tunnels</b></td><td>Local, remote and SOCKS. A switch opens or closes a tunnel on an open connection, with no reconnect.</td></tr>
<tr><td><b>A file browser</b></td><td>This Mac on the left, the server on the right. Drag both ways, also to and from Finder.</td></tr>
<tr><td><b>One encrypted file</b></td><td>AES-256-GCM behind a master password. Put it wherever you sync your files.</td></tr>
<tr><td><b>Touch ID</b></td><td>The key can stay in the Secure Enclave, so unlock is one touch. The password still works on any Mac.</td></tr>
<tr><td><b>Royal TSX import</b></td><td>Folders, connections, key sequences and saved passwords come across, with a report of everything that did not.</td></tr>
<tr><td><b>Agent ready</b></td><td>A bundled <code>termora</code> command lets a script or an AI agent run commands on your servers. No secret reaches the tool.</td></tr>
</table>

## Install

Termora needs macOS 26 or later on Apple silicon.

With [Homebrew](https://brew.sh):

```bash
brew tap fballiano/termora https://github.com/fballiano/termora
brew trust --cask fballiano/termora/termora
brew install --cask fballiano/termora/termora
```

This repository is the tap, so the first command includes its URL. Homebrew
refuses a cask from a tap outside `Homebrew/*` until you trust it, so the
second command is necessary. Always use the full name
`fballiano/termora/termora`: the main cask repository has a different
application that is also called "termora".

To update:

```bash
brew update
brew upgrade --cask fballiano/termora/termora
```

Or download the zip from the
[latest release](https://github.com/fballiano/termora/releases/latest) and
drag **Termora** into **Applications**.

> [!IMPORTANT]
> The application has an ad-hoc signature, not an Apple Developer ID, so macOS
> blocks the first launch. Open **System Settings → Privacy & Security** and
> select **Open Anyway**, or remove the quarantine mark from a terminal:
>
> ```bash
> xattr -dr com.apple.quarantine /Applications/Termora.app
> ```

## Getting started

1. Start Termora and select **Create a document…**. Choose a place for the
   file and a master password. Nobody can recover this password, so keep it
   safe.
2. Add your servers. Press ⌘N for a new connection, or ⇧⌘N for a folder. If
   you use Royal TSX, select **File → Import from Royal TSX…** instead.
3. Double-click a connection to open it. Select **Local Shell** at the top of
   the sidebar, or press ⇧⌘T, for a shell on your Mac.

On a different Mac, select **Open a document…** and give the same file and
password.

## Bookmarks and folders

The sidebar holds a tree of folders and connections. A folder gives its
settings to everything inside it: user name, password or key, jump host,
agent forwarding, compression, X11 forwarding, keep-alive, host key policy,
colour tag, the command before connecting, and the text after connecting. A connection overrides only what it sets itself. The editor
shows where each value comes from.

- A double-click on a connection opens it.
- A right-click offers the other actions: connect, browse files, edit,
  duplicate, and delete.
- Drag a row to move it into a folder or out of one.
- The filter at the top finds connections by name or by host.
- A green dot shows a connection with an open session.

The editor opens as a sheet over the window, so the terminal keeps its room.
Changes apply immediately.

**Before connecting** is a command that runs on this Mac before the
connection opens, for example to open a firewall. **After connecting** is
text that Termora types into the session when the prompt appears. It accepts
key names such as `{ENTER}`, `{TAB}`, `{ESC}`, the arrow names, and
`{DELAY:500}`.

## Tabs, splits and local shells

Every connection opens in a tab in the title bar. A tab can hold several
panes side by side or one above the other.

**⌘T** opens a new tab like the one in front:

- On a connection tab, it opens the same connection again. The new tab uses
  the open connection, so nothing asks for a password, and the command before
  connecting does not run again.
- On a local tab, it opens a local shell in the same folder.
- With no tab open, it opens a local shell in your home folder.

**⇧⌘T** always opens a local shell. So does **Local Shell** at the top of the
sidebar.

A local tab runs your login shell on this Mac, with the same Ghostty engine
and configuration. Its tab shows the name of the current folder, and a split
opens in the same folder. When you type `exit`, the pane closes.

## Keyboard shortcuts

| Keys | Action |
| --- | --- |
| ⌘N | New connection |
| ⇧⌘N | New folder |
| ⌘T | New tab like the one in front |
| ⇧⌘T | New local shell |
| ⌘↩ | Connect to the selected bookmark |
| ⇧⌘F | Browse the files of the selected bookmark |
| ⌘D | Split right |
| ⇧⌘D | Split down |
| ⌘1 … ⌘9 | Go to tab 1 … 9 |
| ⇧⌘] or ⌥⌘→ | Next tab |
| ⇧⌘[ or ⌥⌘← | Previous tab |
| ⌘W | Close the tab |
| ⇧⌘W | Close the window |
| ⌃⌘L | Lock the document |

## Tunnels

A connection holds a list of tunnels: local, remote, or dynamic (SOCKS). You
edit them in the editor of the connection.

When the connection is closed, a checkbox decides if a tunnel opens with it.
When the connection is open, the checkbox becomes a switch that opens or
closes that tunnel immediately. Nothing reconnects.

Every row says in words what the tunnel does, for example
`localhost:8080 → localhost:80`, so you can see two ports in the wrong order
before you connect. The editor also tells you about a port that OpenSSH will
refuse, and about two tunnels on the same port.

## Files

**Session → Browse Files** (⇧⌘F) opens a file browser in its own tab. This
Mac is on the left and the server is on the right. The browser uses the open
connection, so nothing asks for a password again, and it does not disturb
your terminal panes.

- Drag files or folders from one side to the other to copy them. A progress
  bar shows the whole copy, also for a large folder.
- Drag files from Finder into the list to copy them to the server, and drag
  rows out of the list to copy them to Finder.
- Rename, make folders, and delete on both sides.
- Double-click a remote file to open it in an application on your Mac. When
  you save it, Termora copies it back. If the file changed on the server in
  the meantime, Termora asks before it overwrites it.

A folder copy leaves out symbolic links, so a link that points to its own
parent cannot make the copy run forever. The count of skipped links shows at
the end.

## Terminal appearance

Termora reads your own Ghostty configuration file, so a pane looks the same as
your Ghostty window. It looks in this order:

1. `$XDG_CONFIG_HOME/ghostty/config`
2. `~/.config/ghostty/config`
3. `~/Library/Application Support/com.mitchellh.ghostty/config`

Fonts, colours, and a `theme = <name>` line all work, also in the
`light:One,dark:Two` form. Termora never writes to the file.

Ghostty calls itself `xterm-ghostty`, and most servers do not know that name.
Programs such as `htop`, `vim`, and `less` then stop with
`Error opening terminal`. To prevent this, Termora installs the description
on each server one time, in `~/.terminfo` in your home folder there. If the
server cannot accept it (no `tic`, or a read-only home folder), Termora uses
`xterm-256color`, which every server knows.

## Security

- **One encrypted file.** The document is sealed with AES-256-GCM. The key
  comes from your master password through PBKDF2-HMAC-SHA512 with 600,000
  rounds. Every host name and every secret is inside the sealed part.
- **Touch ID.** You can unlock with Touch ID. The key then stays sealed by
  the Secure Enclave of this Mac. The master password still opens the file on
  any Mac.
- **Lock.** Select the lock in the title bar, or press ⌃⌘L. In
  **Settings**, the document can also lock after a time of rest or when the
  Mac sleeps. A lock closes every session and every tunnel.
- **No secret on a command line.** Termora gives each password to OpenSSH
  through `SSH_ASKPASS` and a private socket. A password never goes into a
  command line, into the environment, or into a file.
- **Your own OpenSSH.** Termora runs `/usr/bin/ssh`. It does not have its own
  SSH or SFTP cryptography.

## Driving Termora from an agent or a script

The application includes a small command-line tool, `termora`. A script or
an AI agent can use it to list your bookmarks and to run commands on your
servers. The tool never sees a password: it sends one request to the running
application, and the application does the rest.

A Homebrew install puts `termora` on your PATH. Without Homebrew, call
`/Applications/Termora.app/Contents/MacOS/termora-cli`.

```bash
termora list                  # every bookmark, one per line
termora status                # every open connection: name, state, tunnels
termora run web1 -- uptime    # run a command on a bookmark
```

`run` opens the connection when it is closed, the same as a double-click. If
OpenSSH needs an answer, the question appears in Termora, and the tool waits.
The output streams as it arrives, and the exit code of the remote command
becomes the exit code of `termora`.

The tool works only while a document is open. When the document is locked,
the tool gets no data, not even the bookmark names. Exit code 2 means that
Termora is not running, that the document is locked, or that Termora refused
the request. The reason is on standard error.

### Teaching your agent

`termora --help` prints the whole contract: the three commands, the format of
the output, the exit codes, and the rule that no password reaches the tool.
Most agents read the help before they use a command, so this is often enough.

The `Agents/` folder holds the same text in the format of each agent:

| Agent | How to install it |
|---|---|
| Claude Code | `/plugin marketplace add fballiano/termora`, then `/plugin install termora@termora` |
| Codex, Amp, Zed, and others | Paste `Agents/AGENTS.snippet.md` into your `AGENTS.md` |
| Gemini CLI | `gemini extensions install https://github.com/fballiano/termora` |
| Cursor | Copy `Agents/cursor/termora.mdc` into `.cursor/rules/` |

The shortest form, for a project `AGENTS.md` or `CLAUDE.md`:

```
`termora run <bookmark> -- <command…>` runs a command on a saved SSH server; `termora list` names the bookmarks.
```

Most agents ask before they run a new command. In Claude Code the permission
is `Bash(termora:*)`. Without it, the agent reports that the command was
blocked. That is not a Termora problem.

## Importing from Royal TSX

**File → Import from Royal TSX…** reads an `.rtsz` document and adds its
folders and connections to the open document. Nothing in the open document
is removed. A connection that took its credentials from a folder in Royal TSX
still takes them from that folder in Termora.

**Passwords.** Royal TSX encrypts saved passwords in a private format.
Termora does not try to read that format: it asks Royal TSX for each
password through AppleScript. The first time, macOS asks if Termora can
control Royal TSX. Answer yes. If Royal TSX is not installed or refuses, the
import still runs, and the report names each entry whose password you must
type.

**The report.** Nothing is dropped without a word. The report lists the
entries that did not come across and why (for example Telnet, a serial port,
or an entry in the trash), the passwords that Royal TSX did not give, and the
settings that Termora does not have.

**Key sequences.** A key sequence written in the entry comes across as it
is, for example `cd /opt/app{ENTER}`, and becomes the text after connecting.
A key sequence that was off in Royal TSX stays off, and its text goes into
the notes. A key sequence that Royal TSX keeps by name only cannot come
across, and the report names it.

**Tasks.** A Royal TSX task that runs before connecting becomes the command
before connecting. Termora refuses a task that puts `$PASSWORD$` on its
command line, because every process on the Mac can read a command line. A
task that runs after disconnecting is reported, not imported.

**Key or password.** Royal TSX lets an entry have a private key and a
password at the same time. A Termora connection uses one method, so the
import asks which one to keep. The default is the password, because you can
type a key path again, but you cannot recover a lost password.

## Building from source

See [Docs/DEVELOPMENT.md](Docs/DEVELOPMENT.md) for the build, the tests, the
code layout, and the design notes.

## Licence

MIT. See [LICENSE](LICENSE).
