//
//  ConnectionsFile.swift
//  ShellyardModel
//

import Foundation

/// The public JSON form of a list of connections.
///
/// The export writes it, and the import reads it. A future sync from a web
/// address will read the same form. `Docs/CONNECTIONS-FORMAT.md` is the
/// specification; change the two together.
///
/// The form is a tree, so a person or a script can write it by hand. The
/// order in each `items` array is the order in the sidebar. A setting that
/// is not in the file inherits from the parent folder.
///
/// The internal document JSON is not used here on purpose. It is a flat list
/// joined by `parentID`, and it carries fields that only older versions of
/// the application need.
public struct ConnectionsFile: Hashable, Sendable {
    /// The value of the `format` field.
    public static let formatName = "shellyard.connections"
    /// Raise this number only when an older reader could misread a new file.
    public static let currentVersion = 1

    public var items: [Item]

    public init(items: [Item] = []) {
        self.items = items
    }

    /// One entry of the tree.
    public indirect enum Item: Hashable, Sendable {
        /// A folder and its contents. The `parentID` and the `position` of
        /// the folder mean nothing here: the import sets them.
        case folder(Folder, externalID: String?, items: [Item])
        /// A connection. The `parentID` and the `position` mean nothing here.
        case connection(Connection, externalID: String?)
        /// An entry that the reader could not use. The import reports it,
        /// and the writer leaves it out.
        case invalid(name: String?, reason: String)
    }
}

/// Why a whole file could not be read.
public enum ConnectionsFileError: Error, Equatable, LocalizedError {
    /// The file is not JSON, or the `format` field is wrong.
    case notAConnectionsFile
    /// A newer version of Shellyard wrote the file.
    case newerVersion(Int)

    public var errorDescription: String? {
        switch self {
        case .notAConnectionsFile:
            "This file is not a Shellyard connections file."
        case let .newerVersion(version):
            "This file uses version \(version) of the format. Update Shellyard to import it."
        }
    }
}

// MARK: - Reading and writing

extension ConnectionsFile {
    /// Reads a file. A damaged entry does not stop the read: it becomes an
    /// `.invalid` item, and the other entries still come through.
    public static func decode(_ data: Data) throws -> ConnectionsFile {
        let head: Head
        do {
            head = try JSONDecoder().decode(Head.self, from: data)
        } catch {
            throw ConnectionsFileError.notAConnectionsFile
        }
        guard head.format == formatName else { throw ConnectionsFileError.notAConnectionsFile }
        guard head.version <= currentVersion else {
            throw ConnectionsFileError.newerVersion(head.version)
        }
        return ConnectionsFile(items: head.items?.map(\.item) ?? [])
    }

    /// Writes the file as indented JSON. Invalid items are left out.
    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        return try encoder.encode(Head(
            format: Self.formatName,
            version: Self.currentVersion,
            items: items.map(LossyItem.init)
        ))
    }

    /// The top of the file.
    private struct Head: Codable {
        var format: String
        var version: Int
        var items: [LossyItem]?
    }
}

/// Reads one item and never throws, so one bad entry cannot stop the list.
///
/// A failed `decode` in an unkeyed container does not move to the next
/// element. This wrapper catches the error inside, so the list moves on.
private struct LossyItem: Codable {
    var item: ConnectionsFile.Item

    init(_ item: ConnectionsFile.Item) {
        self.item = item
    }

    init(from decoder: any Decoder) throws {
        do {
            item = try ConnectionsFile.Item.read(from: decoder)
        } catch {
            let name = try? decoder.container(keyedBy: ItemKey.self)
                .decodeIfPresent(String.self, forKey: .name)
            item = .invalid(name: name, reason: describe(error))
        }
    }

    func encode(to encoder: any Encoder) throws {
        try item.write(to: encoder)
    }
}

private enum ItemKey: String, CodingKey {
    case type, id, name, host, port, favorite, settings, forwards, notes, items
}

private enum SettingsKey: String, CodingKey {
    case username, authentication, jumpHost, colorTag, agentForwarding, compression
    case keepAliveSeconds, x11Forwarding, hostKeyPolicy, afterConnectText, beforeConnect
}

private enum AuthenticationKey: String, CodingKey {
    case method, password, path, passphrase
}

private enum CommandKey: String, CodingKey {
    case name, program, arguments, waitForCompletion
}

private enum ForwardKey: String, CodingKey {
    case kind, enabled, bindAddress, listenPort, destinationHost, destinationPort
}

/// A short reason for the import report.
private func describe(_ error: any Error) -> String {
    guard let error = error as? DecodingError else { return error.localizedDescription }
    func path(_ keys: [any CodingKey]) -> String {
        let names = keys.compactMap { $0.intValue == nil ? $0.stringValue : nil }
        return names.isEmpty ? "" : "\(names.joined(separator: ".")): "
    }
    switch error {
    case let .keyNotFound(key, context):
        return "\(path(context.codingPath))the field \"\(key.stringValue)\" is missing."
    case let .typeMismatch(_, context), let .valueNotFound(_, context):
        return "\(path(context.codingPath))the value has the wrong type."
    case let .dataCorrupted(context):
        return "\(path(context.codingPath))\(context.debugDescription)"
    @unknown default:
        return error.localizedDescription
    }
}

/// A value that the reader refuses, with the reason.
private func refuse(_ key: some CodingKey, _ reason: String, path: [any CodingKey]) -> DecodingError {
    .dataCorrupted(.init(codingPath: path + [key], debugDescription: reason))
}

// MARK: Items

extension ConnectionsFile.Item {
    fileprivate static func read(from decoder: any Decoder) throws -> Self {
        let container = try decoder.container(keyedBy: ItemKey.self)
        let type = try container.decode(String.self, forKey: .type)
        let externalID = try container.decodeIfPresent(String.self, forKey: .id)
        let name = try container.decode(String.self, forKey: .name)
        let notes = try container.decodeIfPresent(String.self, forKey: .notes) ?? ""
        let settings = try container.decodeIfPresent(SettingsBox.self, forKey: .settings)?
            .settings ?? .inheritAll

        switch type {
        case "folder":
            let items = try container.decodeIfPresent([LossyItem].self, forKey: .items) ?? []
            let folder = Folder(name: name, settings: settings, notes: notes)
            return .folder(folder, externalID: externalID, items: items.map(\.item))
        case "connection":
            let host = try container.decode(String.self, forKey: .host)
            let port = try container.decodeIfPresent(Int.self, forKey: .port)
            if let port, !PortForward.isValidPort(port) {
                throw refuse(ItemKey.port, "the port must be between 1 and 65535.",
                             path: container.codingPath)
            }
            let favorite = try container.decodeIfPresent(Bool.self, forKey: .favorite) ?? false
            let forwards = try container.decodeIfPresent([ForwardBox].self, forKey: .forwards) ?? []
            let connection = Connection(
                name: name,
                host: host,
                port: port,
                isFavorite: favorite,
                settings: settings,
                forwards: forwards.map(\.forward),
                notes: notes
            )
            return .connection(connection, externalID: externalID)
        default:
            throw refuse(ItemKey.type,
                         "the type must be \"folder\" or \"connection\", not \"\(type)\".",
                         path: container.codingPath)
        }
    }

    fileprivate func write(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: ItemKey.self)
        switch self {
        case let .folder(folder, externalID, items):
            try container.encode("folder", forKey: .type)
            try container.encodeIfPresent(externalID, forKey: .id)
            try container.encode(folder.name, forKey: .name)
            if folder.settings != .inheritAll {
                try container.encode(SettingsBox(settings: folder.settings), forKey: .settings)
            }
            if !folder.notes.isEmpty { try container.encode(folder.notes, forKey: .notes) }
            let kept = items.filter { if case .invalid = $0 { false } else { true } }
            try container.encode(kept.map(LossyItem.init), forKey: .items)
        case let .connection(connection, externalID):
            try container.encode("connection", forKey: .type)
            try container.encodeIfPresent(externalID, forKey: .id)
            try container.encode(connection.name, forKey: .name)
            try container.encode(connection.host, forKey: .host)
            try container.encodeIfPresent(connection.port, forKey: .port)
            if connection.isFavorite { try container.encode(true, forKey: .favorite) }
            if connection.settings != .inheritAll {
                try container.encode(SettingsBox(settings: connection.settings), forKey: .settings)
            }
            if !connection.forwards.isEmpty {
                try container.encode(connection.forwards.map(ForwardBox.init), forKey: .forwards)
            }
            if !connection.notes.isEmpty { try container.encode(connection.notes, forKey: .notes) }
        case .invalid:
            // The parent filters these out, so this never runs. An empty
            // object is still valid JSON if it ever does.
            break
        }
    }
}

// MARK: Settings

/// A setting that is not in the file inherits. A setting that is `null`
/// inherits too, so a script can write every field.
private struct SettingsBox: Codable {
    var settings: NodeSettings

    init(settings: NodeSettings) {
        self.settings = settings
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: SettingsKey.self)
        func read<Value: Decodable>(_ type: Value.Type, _ key: SettingsKey) throws -> Inherited<Value> {
            try container.decodeIfPresent(type, forKey: key).map(Inherited.value) ?? .inherit
        }
        settings = NodeSettings(
            username: try read(String.self, .username),
            authentication: try container.decodeIfPresent(AuthenticationBox.self, forKey: .authentication)
                .map { .value($0.authentication) } ?? .inherit,
            jumpHost: try read(String.self, .jumpHost),
            colorTag: try read(ColorTag.self, .colorTag),
            agentForwarding: try read(Bool.self, .agentForwarding),
            compression: try read(Bool.self, .compression),
            keepAliveSeconds: try read(Int.self, .keepAliveSeconds),
            x11Forwarding: try read(Bool.self, .x11Forwarding),
            hostKeyPolicy: try read(HostKeyPolicy.self, .hostKeyPolicy),
            afterConnectText: try read(String.self, .afterConnectText),
            beforeConnect: try container.decodeIfPresent(CommandBox.self, forKey: .beforeConnect)
                .map { .value($0.command) } ?? .inherit
        )
        if case let .value(seconds) = settings.keepAliveSeconds, seconds < 0 {
            throw refuse(SettingsKey.keepAliveSeconds,
                         "the value must be zero or more.", path: container.codingPath)
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: SettingsKey.self)
        try container.encodeIfPresent(settings.username.ownValue, forKey: .username)
        try container.encodeIfPresent(
            settings.authentication.ownValue.map(AuthenticationBox.init), forKey: .authentication
        )
        try container.encodeIfPresent(settings.jumpHost.ownValue, forKey: .jumpHost)
        try container.encodeIfPresent(settings.colorTag.ownValue, forKey: .colorTag)
        try container.encodeIfPresent(settings.agentForwarding.ownValue, forKey: .agentForwarding)
        try container.encodeIfPresent(settings.compression.ownValue, forKey: .compression)
        try container.encodeIfPresent(settings.keepAliveSeconds.ownValue, forKey: .keepAliveSeconds)
        try container.encodeIfPresent(settings.x11Forwarding.ownValue, forKey: .x11Forwarding)
        try container.encodeIfPresent(settings.hostKeyPolicy.ownValue, forKey: .hostKeyPolicy)
        try container.encodeIfPresent(settings.afterConnectText.ownValue, forKey: .afterConnectText)
        try container.encodeIfPresent(
            settings.beforeConnect.ownValue.map(CommandBox.init), forKey: .beforeConnect
        )
    }
}

/// `{"method": "password", "password": "…"}` and the other three forms.
/// An empty secret is left out of the file.
private struct AuthenticationBox: Codable {
    var authentication: Authentication

    init(_ authentication: Authentication) {
        self.authentication = authentication
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: AuthenticationKey.self)
        let method = try container.decode(String.self, forKey: .method)
        func secret(_ key: AuthenticationKey) throws -> Secret {
            Secret(try container.decodeIfPresent(String.self, forKey: key) ?? "")
        }
        switch method {
        case "agent":
            authentication = .agent
        case "sshConfig":
            authentication = .sshConfig
        case "password":
            authentication = .password(try secret(.password))
        case "privateKey":
            authentication = .privateKey(
                path: try container.decode(String.self, forKey: .path),
                passphrase: try secret(.passphrase)
            )
        default:
            throw refuse(AuthenticationKey.method,
                         "the method must be agent, sshConfig, password, or privateKey, "
                            + "not \"\(method)\".",
                         path: container.codingPath)
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: AuthenticationKey.self)
        switch authentication {
        case .agent:
            try container.encode("agent", forKey: .method)
        case .sshConfig:
            try container.encode("sshConfig", forKey: .method)
        case let .password(secret):
            try container.encode("password", forKey: .method)
            if !secret.isEmpty { try container.encode(secret.value, forKey: .password) }
        case let .privateKey(path, passphrase):
            try container.encode("privateKey", forKey: .method)
            try container.encode(path, forKey: .path)
            if !passphrase.isEmpty { try container.encode(passphrase.value, forKey: .passphrase) }
        }
    }
}

/// The command run on this Mac before the connection opens.
private struct CommandBox: Codable {
    var command: LocalCommand

    init(_ command: LocalCommand) {
        self.command = command
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CommandKey.self)
        command = LocalCommand(
            name: try container.decodeIfPresent(String.self, forKey: .name) ?? "",
            launchPath: try container.decodeIfPresent(String.self, forKey: .program) ?? "",
            arguments: try container.decodeIfPresent(String.self, forKey: .arguments) ?? "",
            waitsForCompletion: try container.decodeIfPresent(Bool.self, forKey: .waitForCompletion)
                ?? true
        )
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CommandKey.self)
        if !command.name.isEmpty { try container.encode(command.name, forKey: .name) }
        try container.encode(command.launchPath, forKey: .program)
        if !command.arguments.isEmpty { try container.encode(command.arguments, forKey: .arguments) }
        try container.encode(command.waitsForCompletion, forKey: .waitForCompletion)
    }
}

// MARK: Tunnels

private struct ForwardBox: Codable {
    var forward: PortForward

    init(_ forward: PortForward) {
        self.forward = forward
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: ForwardKey.self)
        forward = PortForward(
            kind: try container.decode(PortForward.Kind.self, forKey: .kind),
            isEnabled: try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true,
            bindAddress: try container.decodeIfPresent(String.self, forKey: .bindAddress) ?? "",
            listenPort: try container.decode(Int.self, forKey: .listenPort),
            destinationHost: try container.decodeIfPresent(String.self, forKey: .destinationHost) ?? "",
            destinationPort: try container.decodeIfPresent(Int.self, forKey: .destinationPort) ?? 0
        )
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: ForwardKey.self)
        try container.encode(forward.kind, forKey: .kind)
        if !forward.isEnabled { try container.encode(false, forKey: .enabled) }
        if !forward.bindAddress.isEmpty { try container.encode(forward.bindAddress, forKey: .bindAddress) }
        try container.encode(forward.listenPort, forKey: .listenPort)
        if forward.usesDestination {
            try container.encode(forward.destinationHost, forKey: .destinationHost)
            try container.encode(forward.destinationPort, forKey: .destinationPort)
        }
    }
}
