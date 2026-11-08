---
name: shellyard
description: Run a command on a saved SSH server, list the saved servers, or show the open connections, through the Shellyard application on macOS. Use when the user names a server, a host, or a bookmark, or asks to run a command remotely, to check a service, to read a log, or to deploy. Triggers on "shellyard", "on the server", "on production", "ssh into", "remote host", "my bookmarks".
---

# Shellyard

Shellyard is a macOS SSH connection manager. It holds the user's bookmarks and
it keeps one SSH control master for each open connection. The `shellyard`
command asks the running application to use one of those connections.

Prefer `shellyard` over a direct `ssh` call. Shellyard already holds the host,
the port, the user, the key, and the jump host. A direct `ssh` call does not.

## The commands

```bash
shellyard list                  # every bookmark, one per line
shellyard status                # every open connection
shellyard run <bookmark> -- <command...>
```

Run `shellyard --help` for the full contract.

### list

Each line is one bookmark. A bookmark inside folders prints as
`Prod / Web / web1`. Use `list` first when the user names a server that you
do not know yet.

### status

Each line holds the name, a tab, the state, a tab, and the number of open
tunnels. The state is `idle`, `connecting`, `connected`, `failed`, or
`disconnected`.

### run

```bash
shellyard run web1 -- uptime
shellyard run "Prod / Web / web1" -- systemctl is-active nginx
```

Give the full name that `list` prints. A bare name also works when it is
unique. Put every word of the command after `--`.

Shellyard opens the connection when it is closed. The output streams through.
The exit code of `shellyard run` is the exit code of the far command.

## Rules

- Never ask the user for a password or a passphrase. Shellyard asks in its own
  window. A password never reaches this command.
- Never put a secret on the command line. The far shell writes the command
  line into the shell history and into the process list.
- Ask the user before you run a command that changes state on a server.
  Examples: a restart, a delete, a migration, a deploy.
- Read one file with `cat`. Do not open an editor. The command is not
  interactive in this context.

## When the command fails

Exit code 2 means one of three things:

| Message | What to do |
|---|---|
| Shellyard is not running, or the document is locked. | Ask the user to open Shellyard and to unlock the document. |
| No bookmark is named "…". | Run `shellyard list` and use a name from the output. |
| N bookmarks are named "…". | Use the full `Folder / Name` form. |

If the shell refuses the command itself, the agent lacks permission to run
`shellyard`. Ask the user to allow it. In Claude Code the permission is
`Bash(shellyard:*)`.
