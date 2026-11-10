# The Shellyard connections format

This document specifies the JSON file that Shellyard writes when you export
connections, and reads when you import them. A future sync from a web
address will use the same format. A person or a script can write the file by
hand.

The code is `ConnectionsFile` in `Packages/ShellyardModel`. When you change
the format, change this document and the code together.

## An example

```json
{
  "format": "shellyard.connections",
  "version": 1,
  "items": [
    {
      "type": "folder",
      "id": "prod",
      "name": "Production",
      "settings": {
        "username": "deploy",
        "authentication": { "method": "privateKey", "path": "~/.ssh/id_ed25519" },
        "jumpHost": "bastion.example.com",
        "colorTag": "red"
      },
      "items": [
        {
          "type": "connection",
          "id": "web-1",
          "name": "web-1",
          "host": "10.0.1.11",
          "port": 2222,
          "favorite": true,
          "settings": { "keepAliveSeconds": 30 },
          "forwards": [
            { "kind": "local", "listenPort": 8080,
              "destinationHost": "localhost", "destinationPort": 80 }
          ],
          "notes": "Front end"
        }
      ]
    }
  ]
}
```

## General rules

- The file is UTF-8 JSON.
- The reader ignores a field that it does not know. A file from a newer
  version then still imports, without the new fields.
- The order in each `items` array is the order in the sidebar.
- A field that is not in the file has its default value. For a setting, the
  default is "inherit from the parent folder".
- A `null` value has the same effect as a field that is not there.

## The top level

| Field     | Type   | Required | Meaning                                         |
|-----------|--------|----------|-------------------------------------------------|
| `format`  | string | yes      | Always `"shellyard.connections"`.               |
| `version` | number | yes      | The version of the format. Now `1`.             |
| `items`   | array  | no       | The folders and connections at the top level.   |

The reader refuses the file when `format` is wrong. It also refuses a file
with a `version` higher than the version that it knows. Raise the version
only when an older reader could misread a new file. A new optional field
does not need a new version.

## An item

Each item is a folder or a connection. The `type` field tells which.

### Fields of each item

| Field      | Type   | Required | Meaning                                       |
|------------|--------|----------|-----------------------------------------------|
| `type`     | string | yes      | `"folder"` or `"connection"`.                 |
| `id`       | string | no       | A stable identity. See "The id field".        |
| `name`     | string | yes      | The name in the sidebar.                      |
| `settings` | object | no       | See "Settings".                               |
| `notes`    | string | no       | Free text. The default is empty.              |

### Fields of a folder

| Field   | Type  | Required | Meaning                                         |
|---------|-------|----------|-------------------------------------------------|
| `items` | array | no       | The folders and connections inside the folder.  |

### Fields of a connection

| Field      | Type    | Required | Meaning                                       |
|------------|---------|----------|-----------------------------------------------|
| `host`     | string  | yes      | The host name or the address.                 |
| `port`     | number  | no       | 1 to 65535. When there is no port, OpenSSH uses the `Port` line of `~/.ssh/config`, or 22. |
| `favorite` | boolean | no       | The default is `false`.                       |
| `forwards` | array   | no       | The tunnels. See "Tunnels".                   |

### The id field

The export writes the internal identifier of each node, a UUID. A script can
write any string, for example the name of a server in an inventory. The
string must be unique in the file.

The import of version 1 does not use the `id`. It gives each node a new
identifier, so you can import the same file two times. A future sync will use
the `id` to find a connection that it made before. It can then change that
connection, and not add a second copy.

## Settings

A folder and a connection have the same settings. A connection takes each
setting that it does not set from the nearest folder above it that sets it.
To stop an inherited value, set an empty value. For example, `"jumpHost": ""`
means "no jump host".

| Field              | Type    | Meaning                                                   |
|--------------------|---------|-----------------------------------------------------------|
| `username`         | string  | The user name on the server.                              |
| `authentication`   | object  | See "Authentication".                                     |
| `jumpHost`         | string  | `user@host` or `host`. Empty means no jump host.          |
| `colorTag`         | string  | `none`, `red`, `orange`, `yellow`, `green`, `blue`, `purple`, or `grey`. |
| `agentForwarding`  | boolean | Forward the SSH agent.                                    |
| `compression`      | boolean | Compress the connection.                                  |
| `keepAliveSeconds` | number  | Seconds between keep-alive messages. Zero turns them off. |
| `x11Forwarding`    | boolean | Forward X11.                                              |
| `hostKeyPolicy`    | string  | `ask`, `strict`, or `acceptNew`.                          |
| `afterConnectText` | string  | Text typed into the session after it opens, for example `cd /var/www{ENTER}`. |
| `beforeConnect`    | object  | A command that runs on this Mac. See "Commands".          |

### Authentication

| `method`     | Other fields                      | Meaning                                  |
|--------------|-----------------------------------|------------------------------------------|
| `agent`      | none                              | Use the keys of the running `ssh-agent`. |
| `sshConfig`  | none                              | Let OpenSSH decide from `~/.ssh/config`. |
| `password`   | `password` (string, optional)     | Send this password.                      |
| `privateKey` | `path` (string, required), `passphrase` (string, optional) | Use this key file. |

An export without passwords writes the method, but not `password` or
`passphrase`. After the import, Shellyard lists the connections that need a
password.

The key file does not go in the export, only its path. The other Mac must
have the key at the same path.

### Commands

| Field               | Type    | Required | Meaning                                       |
|---------------------|---------|----------|-----------------------------------------------|
| `program`           | string  | yes      | The full path of the program.                 |
| `arguments`         | string  | no       | The arguments, as one line.                   |
| `name`              | string  | no       | The name shown while the command runs.        |
| `waitForCompletion` | boolean | no       | Wait before connecting. The default is `true`. |

The arguments can contain `$HOST$`, `$PORT$`, `$USERNAME$`, and `$NAME$`.
Shellyard never starts a shell, so a mark cannot become a second command.

A command runs a program on the Mac of the person who imports the file. The
import therefore removes every command, unless the person turns on "Keep the
commands that run on this Mac". The import always removes a command that
contains `$PASSWORD$`, `$PASSPHRASE$`, or `$CREDENTIALPASSWORD$`.

## Tunnels

| Field             | Type    | Required | Meaning                                         |
|-------------------|---------|----------|-------------------------------------------------|
| `kind`            | string  | yes      | `local`, `remote`, or `dynamic`.                |
| `listenPort`      | number  | yes      | The port that listens.                          |
| `bindAddress`     | string  | no       | The address that listens. The default is `localhost`. |
| `destinationHost` | string  | for `local` and `remote` | The far end.            |
| `destinationPort` | number  | for `local` and `remote` | The port of the far end. |
| `enabled`         | boolean | no       | The default is `true`.                          |

## Errors

The reader refuses the whole file only when the file is not JSON, when
`format` is wrong, or when `version` is too high.

A problem in one item does not stop the import. The item and everything in
it are left out, and the report shows the name of the item and the reason.
These are problems in an item:

- A required field is missing.
- A field has the wrong type.
- `type`, `method`, `colorTag`, `hostKeyPolicy`, or `kind` has a value that
  is not in this document.
- `port` is not between 1 and 65535, or `keepAliveSeconds` is less than 0.

## Passwords in the file

The file is plain text. When the export includes passwords, anybody who can
read the file can read the passwords. Shellyard writes the file with mode
0600, so only your user account can read it. Delete the file after the
import.
