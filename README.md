<div align="center">
<img src="Docs/icon.png" width="128" alt="Shellyard" />
<h1>Shellyard</h1>
<p><strong>An SSH connection manager for macOS, built on the Ghostty terminal engine.</strong></p>
<p>
<a href="https://github.com/fballiano/shellyard/releases/latest"><img src="https://img.shields.io/github/v/release/fballiano/shellyard?style=for-the-badge&color=1E8A5F&labelColor=1B1F23" alt="Latest release" /></a>
<a href="https://github.com/fballiano/shellyard/releases"><img src="https://img.shields.io/github/downloads/fballiano/shellyard/total?style=for-the-badge&color=1E8A5F&labelColor=1B1F23" alt="Downloads" /></a>
<img src="https://img.shields.io/badge/macOS-26%2B-1E8A5F?style=for-the-badge&labelColor=1B1F23&logo=apple&logoColor=white" alt="macOS 26 or later" />
<a href="LICENSE"><img src="https://img.shields.io/badge/licence-MIT-1E8A5F?style=for-the-badge&labelColor=1B1F23" alt="MIT licence" /></a>
</p>
<p><a href="https://github.com/fballiano/shellyard/releases/latest"><img src="https://img.shields.io/badge/Download%20for%20macOS-1E8A5F?style=for-the-badge&labelColor=1E8A5F&logo=data:image/svg%2Bxml;base64,PHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHZpZXdCb3g9IjAgMCAyNCAyNCIgZmlsbD0ibm9uZSIgc3Ryb2tlPSIjZmZmIiBzdHJva2Utd2lkdGg9IjIiIHN0cm9rZS1saW5lY2FwPSJyb3VuZCIgc3Ryb2tlLWxpbmVqb2luPSJyb3VuZCI+PHBhdGggZD0iTTQgMTd2MmEyIDIgMCAwIDAgMiAyaDEyYTIgMiAwIDAgMCAyIC0ydi0yIi8+PHBhdGggZD0iTTcgMTFsNSA1bDUgLTUiLz48cGF0aCBkPSJNMTIgNGwwIDEyIi8+PC9zdmc+" alt="Download for macOS" height="36" /></a></p>
</div>

<table align=center><tr><td align=center>
<strong>If you find my work valuable, please consider sponsoring</strong><br />
<a href="https://github.com/sponsors/fballiano" target=_blank title="Sponsor me on GitHub"><img src="https://img.shields.io/badge/sponsor-30363D?style=for-the-badge&logo=GitHub-Sponsors&logoColor=#white" alt="Sponsor me on GitHub" /></a>
<a href="https://www.buymeacoffee.com/fballiano" target=_blank title="Buy me a coffee"><img src="https://img.shields.io/badge/Buy_Me_A_Coffee-FFDD00?style=for-the-badge&logo=buy-me-a-coffee&logoColor=black" alt="Buy me a coffee" /></a>
<a href="https://www.paypal.com/paypalme/fabrizioballiano" target=_blank title="Donate via PayPal"><img src="https://img.shields.io/badge/PayPal-00457C?style=for-the-badge&logo=paypal&logoColor=white" alt="Donate via PayPal" /></a>
</td></tr></table>

---

Shellyard keeps your servers in one encrypted file and opens them in tabs, with
the Ghostty terminal engine and your own Ghostty configuration. A local shell
sits next to your servers, so all of your terminal work stays in one window.

Shellyard does not have its own SSH. It drives the OpenSSH of macOS, so your
`~/.ssh/config`, your keys, your SSH agent, and your jump hosts work as they
are.

## Highlights

- **Your servers in a tree.** Folders hold connections, and a folder gives
  its user name, password, key, and other settings to everything inside it.
  Colour tags mark production at a glance.
- **One login per server.** Tabs, splits, tunnels, and the file browser all
  share one connection, so you type a password or touch a key one time.
- **A real terminal.** The Ghostty engine reads your Ghostty configuration
  and theme. Tabs, splits, and local shells, with the shortcuts you know.
- **Tunnels with a switch.** Local, remote, and SOCKS tunnels open and close
  on a live connection, with no reconnect.
- **Files on both sides.** This Mac on the left, the server on the right.
  Drag files across, to Finder, and from Finder. Edit a remote file in any
  application on your Mac.
- **Secrets stay secret.** One file sealed with AES-256-GCM. Unlock with
  Touch ID. Passwords never go on a command line.
- **Scripts and AI agents.** `shellyard run web1 -- uptime` runs a command on a
  saved server, and the tool never sees a password.
- **Coming from Royal TSX.** The import brings your folders, connections, and
  saved passwords, and reports everything that did not come across.

## Install

Shellyard needs macOS 26 or later on Apple silicon.

```bash
brew tap fballiano/tap
brew trust --tap fballiano/tap
brew install --cask shellyard
```

To update:

```bash
brew update
brew upgrade --cask shellyard
```

Or download the zip from the
[latest release](https://github.com/fballiano/shellyard/releases/latest) and
drag **Shellyard** into **Applications**.

Shellyard is signed with an Apple Developer ID and notarized by Apple, so it
opens like any other application.

## Getting started

1. Start Shellyard and select **Create a document…**. Choose where to keep the
   file and a master password.
2. Add your servers: ⌘N for a connection, ⇧⌘N for a folder. From Royal TSX,
   select **File → Import from Royal TSX…** instead.
3. Double-click a connection to open it.
4. Press ⇧⌘T, or select **Local Shell** at the top of the sidebar, for a
   shell on your Mac.

## Keyboard shortcuts

| Keys | Action |
| --- | --- |
| ⌘T | New tab like the one in front |
| ⇧⌘T | New local shell |
| ⌘D / ⇧⌘D | Split right / split down |
| ⌘1 … ⌘9 | Go to a tab |
| ⇧⌘] / ⇧⌘[ | Next tab / previous tab (also ⌥⌘→ / ⌥⌘←) |
| ⌘W / ⇧⌘W | Close the tab / close the window |
| ⌘O | Open a connection: find a bookmark, or type `user@host` |
| ⌘↩ | Connect to the selected bookmark |
| ⌘R | Reconnect a tab whose connection closed |
| ⇧⌘F | Browse the files of the selected bookmark |
| ⌘N / ⇧⌘N | New connection / new folder |
| ⌃⌘L | Lock the document |

## Guide

### Bookmarks and folders

Double-click a connection to open it. Right-click a row for the other
actions: connect, browse files, edit, duplicate, and delete. Drag rows to
move them between folders. The filter finds a connection by its name or its
host. A green dot marks a server with an open session.

Leave the port empty to let OpenSSH choose it: the `Port` line of
`~/.ssh/config` for that host, or 22.

A folder gives its settings to everything inside it: user name, password or
key, jump host, agent forwarding, compression, X11 forwarding, keep-alive,
host key policy, colour tag, and the two commands below. A connection
overrides only what it sets itself, and the editor shows where each value
comes from.

- **Before connecting** runs a command on your Mac before the connection
  opens, for example to open a firewall.
- **After connecting** types text into the session when the prompt appears.
  Key names such as `{ENTER}`, `{TAB}`, `{ESC}`, the arrows, and
  `{DELAY:500}` work. Shellyard knows that the prompt is there when the shell
  sets the window title, as fish does, and as bash and zsh do on most
  servers. A shell that sets no title gets the text after 3 seconds.

### Open Connection

Press ⌘O, and type a part of a name, a host, or a folder. Each word that you
type must appear in one of the three. Use ↑ and ↓ to choose a row. Return
opens a terminal, and ⌘↩ opens the file browser. Escape closes the field.

To connect to a server that has no bookmark, type its address:
`host`, `user@host`, `user@host:2222`, or an alias from `~/.ssh/config`.
The last row says **Connect to …**. When the address has a user name, or
when no bookmark matches, that row comes first.

A quick connection uses the default settings and stores no password: OpenSSH
asks for it each time. If you type no port, OpenSSH takes the port from
`~/.ssh/config`. To keep the server, right-click its tab and select
**Save as Bookmark**. The bookmark goes to the top level of the tree, and its
editor opens.

### When a connection closes

If the server goes away or the network drops, every tab on that connection
keeps its panes, so you can still read the last output. A bar over the tab
says why the connection closed. Select **Reconnect**, or press ⌘R, to open
the connection again. All tabs on that connection come back together, and
each split keeps its shape. A new pane starts with an empty screen.

Reconnect runs the command before connecting again, opens the tunnels again,
and types the text after connecting into each tab. If a connection could not
open at all, its tab offers **Try Again**, which ⌘R also does.

When your Mac wakes from sleep, Shellyard reconnects by itself. It waits for
the network, then asks each server if the connection still works, and
reconnects the ones that do not. With **Lock when the Mac sleeps** on, the
document is locked instead, and nothing is open to reconnect.

At other times, Shellyard finds a dead network through keep-alive. With
keep-alive at 0, a dropped connection can stay open for minutes before
Shellyard sees it.

### Tabs, splits and local shells

⌘T opens a new tab like the one in front. On a connection, that is the same
server again, with no new login. On a local shell, it is a local shell in the
same folder. With no tab open, it is a local shell in your home folder.

⇧⌘T, or **Local Shell** in the sidebar, always opens a local shell. A local
tab shows the name of its current folder, and a split opens in that folder.

A tab you cannot see glows when it needs a look. It glows in the accent
colour when a program rings the bell, for example after
`make; printf '\a'`. It glows green when a command of five seconds or more
ends well, and red when that command fails. The green and red marks need a
shell that reports its commands (OSC 133): a local shell does, and so does
fish 4 or later on a server. The glow goes when you open the tab.

### Tunnels

Edit the tunnels of a connection in its editor. While the connection is
closed, a checkbox decides if a tunnel opens with it. While it is open, the
checkbox becomes a switch that opens or closes the tunnel immediately.

Each row says in words what the tunnel does, for example
`localhost:8080 → localhost:80`. The editor warns you about a port that
OpenSSH will refuse and about two tunnels on the same port.

### Files

**Session → Browse Files** (⇧⌘F) opens a file browser in its own tab, on the
same connection as your terminals.

- Drag files and folders between the two sides, to Finder, and from Finder.
  One progress bar covers the whole copy.
- Rename, make folders, and delete on both sides.
- Double-click a remote file to open it in an application on your Mac. When
  you save it, Shellyard copies it back. If the file changed on the server in
  the meantime, Shellyard asks first.

### Terminal appearance

Shellyard reads your Ghostty configuration file, in this order, and never
writes to it:

1. `$XDG_CONFIG_HOME/ghostty/config`
2. `~/.config/ghostty/config`
3. `~/Library/Application Support/com.mitchellh.ghostty/config`

Fonts, colours, and `theme = <name>` all work, also as
`theme = light:One,dark:Two`.

### Security

- The document is sealed with AES-256-GCM. Your master password becomes the
  key through PBKDF2-HMAC-SHA512 with 600,000 rounds. Every host name and
  every secret is inside the sealed part.
- With Touch ID on, the key is sealed by the Secure Enclave of this Mac. The
  master password still opens the file on any Mac.
- The lock in the title bar, or ⌃⌘L, closes every session and every tunnel.
  **Settings** can also lock the document after a time of rest or when the
  Mac sleeps.
- Shellyard gives each password to OpenSSH through `SSH_ASKPASS` and a private
  socket. A password never goes into a command line, into the environment,
  or into a file.

### Scripts and AI agents

The `shellyard` command comes with the application. A Homebrew install puts it
on your PATH. Otherwise, call
`/Applications/Shellyard.app/Contents/MacOS/shellyard-cli`.

```bash
shellyard list                  # every bookmark, one per line
shellyard status                # every open connection: name, state, tunnels
shellyard run web1 -- uptime    # run a command on a bookmark
```

`run` opens the connection if it is closed. If OpenSSH asks a question, the
question appears in Shellyard, and the command waits. The output streams as it
arrives, and the exit code of the remote command is the exit code of
`shellyard`. The command gets nothing while the document is locked. Exit code 2
means that Shellyard is not running, that the document is locked, or that the
request was refused.

`shellyard --help` prints the whole contract, which is often enough for an
agent. For a fixed setup, install the instructions for your agent:

| Agent | How to install it |
|---|---|
| Claude Code | `/plugin marketplace add fballiano/shellyard`, then `/plugin install shellyard@shellyard` |
| Codex, Amp, Zed, and others | Paste `Agents/AGENTS.snippet.md` into your `AGENTS.md` |
| Gemini CLI | `gemini extensions install https://github.com/fballiano/shellyard` |
| Cursor | Copy `Agents/cursor/shellyard.mdc` into `.cursor/rules/` |

In Claude Code, allow the command with the permission `Bash(shellyard:*)`.

### Importing from Royal TSX

**File → Import from Royal TSX…** adds the folders and connections of an
`.rtsz` document to the open document. Nothing that is already there is
removed.

- **Passwords.** Shellyard asks Royal TSX for each saved password through
  AppleScript. The first time, macOS asks if Shellyard can control Royal TSX:
  answer yes. If Royal TSX is not available, the import still runs, and the
  report names each password that you must type.
- **Key sequences** become the text after connecting. **Tasks** before
  connecting become the command before connecting. A task that puts
  `$PASSWORD$` on its command line is refused.
- **Key and password.** Royal TSX lets an entry have both. A Shellyard
  connection uses one, so the import asks which one to keep.
- **The report** lists every entry, password, and setting that did not come
  across, and why.

## FAQ

**Does Shellyard use my `~/.ssh/config`?**
Yes. Shellyard runs `/usr/bin/ssh`, so everything in your SSH configuration
applies: host aliases, keys, certificates, FIDO keys, the agent, and
`known_hosts`.

**Why does Shellyard write a file in `~/.terminfo` on my servers?**
Ghostty says that its terminal type is `xterm-ghostty`, and most servers do
not know that name. Without the description, `htop`, `vim`, and `less` stop
with `Error opening terminal`. Shellyard installs the description one time, in
`~/.terminfo/78/xterm-ghostty`. If a server cannot accept it, Shellyard uses
`xterm-256color` for that server.

**How do I use the same bookmarks on two Macs?**
Put the document in a folder that you sync, such as iCloud Drive, and open
it on the other Mac with **Open a document…** and the same master password.

**Shellyard asked for things again after the update to 1.1.1. Why?**
1.1.1 is the first version signed with a Developer ID, and macOS sees a new
signature as a new application. It can ask one more time for permission to
control Royal TSX during an import. If Touch ID stops opening the document,
type the master password once and turn Touch ID on again in **Settings**.

**I forgot my master password. Can I recover the document?**
No. Nobody can recover the password. If Touch ID is on for the document, it
still opens the document on that Mac, but a new password needs the current
one.

**What happens to my sessions when the document locks?**
Every session and every tunnel closes, local shells too. Nothing stays open
behind a locked document.

**Why is Termora now called Shellyard?**
Another terminal application has the name Termora, and the main Homebrew
cask repository has its cask. Shellyard has your bookmarks, your settings,
and your Touch ID key, and it opens your `.termora` documents as before.

To move a Homebrew install of Termora to Shellyard:

```bash
brew uninstall --cask fballiano/termora/termora
brew install --cask fballiano/tap/shellyard
brew untap fballiano/termora
```

The uninstall removes the application only. Your documents and settings
stay. The command is now `shellyard`, so change `termora` in your scripts and
in the permissions of your AI agents.

## Development

See [Docs/DEVELOPMENT.md](Docs/DEVELOPMENT.md) to build Shellyard, run the
tests, and read about its design.

## Licence

MIT. See [LICENSE](LICENSE).
