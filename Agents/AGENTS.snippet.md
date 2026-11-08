## SSH servers

Shellyard holds the saved SSH servers. Use `shellyard`, not a direct `ssh` call:
Shellyard already holds the host, the port, the user, the key, and the jump
host.

```bash
shellyard list                  # every bookmark, one per line
shellyard status                # every open connection
shellyard run web1 -- uptime    # run a command on a bookmark
```

A bookmark inside folders prints as `Prod / Web / web1`. Use that full name,
or a bare name that is unique. Put every word of the command after `--`. The
exit code of `shellyard run` is the exit code of the far command. Run
`shellyard --help` for the full contract.

Never ask for a password: Shellyard asks in its own window. Ask me before you
run a command that changes state on a server.
