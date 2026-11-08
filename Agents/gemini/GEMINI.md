# Shellyard

Shellyard is a macOS SSH connection manager. It holds the saved servers, and
it keeps one SSH control master for each open connection. The `shellyard`
command asks the running application to use one of those connections.

Use `shellyard` instead of a direct `ssh` call. Shellyard already holds the
host, the port, the user, the key, and the jump host.

```bash
shellyard list                  # every bookmark, one per line
shellyard status                # every open connection
shellyard run web1 -- uptime    # run a command on a bookmark
```

Run `shellyard --help` for the full contract.

A bookmark inside folders prints as `Prod / Web / web1`. Use that full name,
or a bare name that is unique. Put every word of the command after `--`.
The exit code of `shellyard run` is the exit code of the far command.

Rules:

- Never ask the user for a password. Shellyard asks in its own window.
- Never put a secret on the command line.
- Ask the user before you run a command that changes state on a server.

Exit code 2 means that Shellyard is not running, that the document is locked,
or that the bookmark name is wrong. The reason is one line on standard
error.
