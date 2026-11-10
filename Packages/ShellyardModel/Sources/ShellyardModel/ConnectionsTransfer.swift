//
//  ConnectionsTransfer.swift
//  ShellyardModel
//

import Foundation

// MARK: - Export

extension ConnectionsFile {
    /// Makes the file for the whole document, or for one branch of it.
    ///
    /// - Parameters:
    ///   - root: The folder or the connection to export, or `nil` for the
    ///     whole document. A folder goes out with everything inside it.
    ///   - includeSecrets: When false, every password and passphrase is left
    ///     out. The method stays, so the import can name what is missing.
    ///
    /// A branch loses the folders above it, and with them the values it
    /// inherits. The exported top node therefore gets those values written
    /// into its own settings, so its connections behave the same after the
    /// import.
    public init(exporting root: UUID?, from index: DocumentIndex, includeSecrets: Bool) {
        func item(_ node: TreeNode, settings: NodeSettings? = nil, depth: Int = 0) -> Item {
            switch node {
            case var .folder(folder):
                folder.settings = settings ?? folder.settings
                if !includeSecrets { folder.settings.removeSecrets() }
                let children = depth < Document.maximumDepth
                    ? index.children(of: folder.id).map { item($0, depth: depth + 1) }
                    : []
                return .folder(folder, externalID: folder.id.uuidString, items: children)
            case var .connection(connection):
                connection.settings = settings ?? connection.settings
                if !includeSecrets { connection.settings.removeSecrets() }
                return .connection(connection, externalID: connection.id.uuidString)
            }
        }

        guard let root else {
            self.init(items: index.children(of: nil).map { item($0) })
            return
        }
        guard let node = index.node(root) else {
            self.init()
            return
        }
        let settings: NodeSettings = switch node {
        case let .folder(folder):
            index.settingsWithInheritedValues(of: folder.settings, under: folder.parentID)
        case let .connection(connection):
            index.settingsWithInheritedValues(of: connection.settings, under: connection.parentID)
        }
        self.init(items: [item(node, settings: settings)])
    }

    /// The number of folders and connections in the file, at any depth.
    public var counts: (folders: Int, connections: Int) {
        var folders = 0
        var connections = 0
        func walk(_ items: [Item]) {
            for item in items {
                switch item {
                case let .folder(_, _, children):
                    folders += 1
                    walk(children)
                case .connection:
                    connections += 1
                case .invalid:
                    break
                }
            }
        }
        walk(items)
        return (folders, connections)
    }
}

extension NodeSettings {
    /// Empties the password and the passphrase, and keeps the method.
    public mutating func removeSecrets() {
        guard case let .value(method) = authentication else { return }
        switch method {
        case .password:
            authentication = .value(.password(.empty))
        case let .privateKey(path, _):
            authentication = .value(.privateKey(path: path, passphrase: .empty))
        case .agent, .sshConfig:
            break
        }
    }
}

extension DocumentIndex {
    /// The settings of a node, with every inherited value written in.
    ///
    /// A field that the node sets keeps its value. A field that inherits
    /// takes the value of the nearest folder above that sets one. A field
    /// that no folder sets still inherits, so the defaults of the receiving
    /// Mac apply.
    public func settingsWithInheritedValues(
        of settings: NodeSettings,
        under parentID: UUID?
    ) -> NodeSettings {
        let chain = ancestors(ofParent: parentID)
        var result = settings
        func fill<Value>(_ keyPath: WritableKeyPath<NodeSettings, Inherited<Value>>) {
            guard result[keyPath: keyPath].inheritsFromParent else { return }
            if let value = chain.lazy.compactMap({ $0.settings[keyPath: keyPath].ownValue }).first {
                result[keyPath: keyPath] = .value(value)
            }
        }
        fill(\.username)
        fill(\.authentication)
        fill(\.jumpHost)
        fill(\.colorTag)
        fill(\.agentForwarding)
        fill(\.compression)
        fill(\.keepAliveSeconds)
        fill(\.x11Forwarding)
        fill(\.hostKeyPolicy)
        fill(\.afterConnectText)
        fill(\.beforeConnect)
        return result
    }
}

// MARK: - Import

/// What an import adds to a document, and what the person must know first.
///
/// Build one to show the preview, and add its `folders` and `connections`
/// to the document when the person accepts. Every node gets a new
/// identifier, so a file imported two times does not collide with itself.
public struct ConnectionsImport: Sendable {
    /// One line of the report.
    public struct Note: Identifiable, Hashable, Sendable {
        public let id = UUID()
        /// The place of the entry in the file, for example `Prod / web-1`.
        public var path: String
        public var text: String
    }

    public private(set) var folders: [Folder] = []
    public private(set) var connections: [Connection] = []
    /// Entries that the import leaves out, with the reason.
    public private(set) var problems: [Note] = []
    /// Connections and folders that use a password, but have none.
    public private(set) var missingSecrets: [Note] = []
    /// Commands that run on this Mac before a connection opens. The import
    /// keeps them only when the person allows it.
    public private(set) var commands: [Note] = []
    /// Commands that ask for a password. The import always removes them.
    public private(set) var refusedCommands: [Note] = []

    /// - Parameters:
    ///   - file: The file that was read.
    ///   - parent: The folder that receives the entries, or `nil` for the
    ///     top level.
    ///   - firstPosition: The position of the first entry among the children
    ///     of `parent`. Use the end of the list, so nothing moves.
    ///   - keepCommands: Keep the commands that run on this Mac.
    public init(
        file: ConnectionsFile,
        under parent: UUID?,
        firstPosition: Int,
        keepCommands: Bool
    ) {
        add(file.items, under: parent, firstPosition: firstPosition,
            path: [], keepCommands: keepCommands, depth: 0)
    }

    public var isEmpty: Bool { folders.isEmpty && connections.isEmpty }

    private mutating func add(
        _ items: [ConnectionsFile.Item],
        under parent: UUID?,
        firstPosition: Int,
        path: [String],
        keepCommands: Bool,
        depth: Int
    ) {
        guard depth < Document.maximumDepth else { return }
        var position = firstPosition
        for item in items {
            switch item {
            case let .folder(source, _, children):
                var folder = source
                folder.id = UUID()
                folder.parentID = parent
                folder.position = position
                folder.isExpanded = true
                let here = path + [folder.name]
                check(&folder.settings, at: here, keepCommands: keepCommands)
                folders.append(folder)
                add(children, under: folder.id, firstPosition: 0, path: here,
                    keepCommands: keepCommands, depth: depth + 1)
            case let .connection(source, _):
                var connection = source
                connection.id = UUID()
                connection.parentID = parent
                connection.position = position
                connection.forwards = source.forwards.map { forward in
                    var fresh = forward
                    fresh.id = UUID()
                    return fresh
                }
                check(&connection.settings, at: path + [connection.name], keepCommands: keepCommands)
                connections.append(connection)
            case let .invalid(name, reason):
                let here = (path + [name ?? "Entry \(position + 1)"]).joined(separator: " / ")
                problems.append(Note(path: here, text: reason))
                // An entry left out takes no position.
                continue
            }
            position += 1
        }
    }

    /// Notes what a node needs, and removes the commands that must not stay.
    private mutating func check(_ settings: inout NodeSettings, at path: [String], keepCommands: Bool) {
        let place = path.joined(separator: " / ")
        if settings.authentication.ownValue?.needsSecret == true {
            missingSecrets.append(Note(path: place, text: "Type the password in."))
        }
        guard let command = settings.beforeConnect.ownValue, !command.isEmpty else { return }
        let line = [command.launchPath, command.arguments]
            .filter { !$0.isEmpty }.joined(separator: " ")
        if CommandPlaceholders.containsSecretMark(line) {
            refusedCommands.append(Note(
                path: place,
                text: "\(line) — removed, because it puts a password on a command line."
            ))
            settings.beforeConnect = .inherit
        } else {
            commands.append(Note(path: place, text: line))
            if !keepCommands { settings.beforeConnect = .inherit }
        }
    }
}
