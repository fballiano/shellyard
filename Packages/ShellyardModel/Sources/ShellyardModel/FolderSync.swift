//
//  FolderSync.swift
//  ShellyardModel
//

import Foundation

/// Where a synced folder gets its contents.
///
/// A web address returns a `shellyard.connections` file. Its items become
/// the contents of the folder. `Document.applySync` adds, changes, and
/// removes the synced nodes; it never touches a node that the person added.
public struct FolderSync: Codable, Hashable, Sendable {
    public enum Interval: String, Codable, Hashable, Sendable, CaseIterable {
        case manual
        case hourly
        case daily

        /// The time between two automatic syncs, or `nil` for manual.
        public var seconds: TimeInterval? {
            switch self {
            case .manual: nil
            case .hourly: 3600
            case .daily: 86400
            }
        }
    }

    /// The address that returns the file.
    public var url: String
    /// The HTTP Basic user name. Empty sends no credentials.
    public var username: String
    /// The HTTP Basic password.
    public var password: Secret
    public var interval: Interval
    /// Keep what only a trusted server may set: the commands before
    /// connecting, which run a program on this Mac, and agent and X11
    /// forwarding, which give the far host a way back to this Mac. Off unless
    /// the person allows it.
    public var trustsServer: Bool
    /// The ids of the entries that the person deleted, or moved out of the
    /// folder. The sync does not add them again.
    public var excludedIDs: [String]

    public init(
        url: String = "",
        username: String = "",
        password: Secret = .empty,
        interval: Interval = .daily,
        trustsServer: Bool = false,
        excludedIDs: [String] = []
    ) {
        self.url = url
        self.username = username
        self.password = password
        self.interval = interval
        self.trustsServer = trustsServer
        self.excludedIDs = excludedIDs
    }

    private enum CodingKeys: String, CodingKey {
        case url, username, password, interval, trustsServer, excludedIDs
    }

    /// Every field but the address may be missing, so a later version can
    /// add a field without breaking this reader.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        url = try container.decode(String.self, forKey: .url)
        username = try container.decodeIfPresent(String.self, forKey: .username) ?? ""
        password = try container.decodeIfPresent(Secret.self, forKey: .password) ?? .empty
        interval = (try? container.decodeIfPresent(Interval.self, forKey: .interval)) ?? .daily
        trustsServer = try container.decodeIfPresent(Bool.self, forKey: .trustsServer) ?? false
        excludedIDs = try container.decodeIfPresent([String].self, forKey: .excludedIDs) ?? []
    }

    /// The address as a URL, or `nil` when it is not one that the sync uses.
    public var validURL: URL? {
        urlProblem == nil ? URL(string: url.trimmingCharacters(in: .whitespaces)) : nil
    }

    /// Why the address cannot be used, or `nil` when it can.
    ///
    /// Only HTTPS is allowed, because the password and the connections cross
    /// the network. Plain HTTP is allowed for this Mac only, for a local test
    /// server.
    public var urlProblem: String? {
        let text = url.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return "Type the address of the list." }
        guard let components = URLComponents(string: text),
              let scheme = components.scheme?.lowercased(),
              let host = components.host, !host.isEmpty else {
            return "This is not a web address."
        }
        switch scheme {
        case "https":
            return nil
        case "http" where ["localhost", "127.0.0.1", "::1", "[::1]"].contains(host.lowercased()):
            return nil
        case "http":
            return "Use an https address. Plain http is allowed only for localhost."
        default:
            return "Use an https address."
        }
    }
}

/// What a synced node remembers about its source.
public struct SyncLink: Codable, Hashable, Sendable {
    /// The synced folder that made this node.
    public var sourceID: UUID
    /// The `id` of the item in the file.
    public var externalID: String
    /// The values that the file gave the last time. A field that still has
    /// this value was not changed here, so the next sync can replace it. A
    /// field with another value was changed here, and the sync keeps it.
    public var base: SyncedFields

    public init(sourceID: UUID, externalID: String, base: SyncedFields) {
        self.sourceID = sourceID
        self.externalID = externalID
        self.base = base
    }
}

/// The fields of a node that the sync writes. A folder leaves the
/// connection fields empty.
public struct SyncedFields: Codable, Hashable, Sendable {
    public var name: String
    public var host: String
    public var port: Int?
    public var isFavorite: Bool
    public var settings: NodeSettings
    public var forwards: [PortForward]
    public var notes: String

    public init(folder: Folder) {
        name = folder.name
        host = ""
        port = nil
        isFavorite = false
        settings = folder.settings
        forwards = []
        notes = folder.notes
    }

    public init(connection: Connection) {
        name = connection.name
        host = connection.host
        port = connection.port
        isFavorite = connection.isFavorite
        settings = connection.settings
        forwards = connection.forwards
        notes = connection.notes
    }
}

/// Why a sync changed nothing.
public enum SyncError: Error, Equatable, LocalizedError {
    case folderNotFound
    case notSynced
    /// The file holds no usable item, and the folder holds synced items. An
    /// empty answer is more often a fault of the server than the truth.
    case wouldRemoveEverything(Int)

    public var errorDescription: String? {
        switch self {
        case .folderNotFound:
            "The folder no longer exists."
        case .notSynced:
            "The folder has no sync address."
        case let .wouldRemoveEverything(count):
            "The list is empty, so the sync would remove all \(count) synced entries. "
                + "Shellyard changed nothing. Check the server."
        }
    }
}

/// What a sync did.
public struct SyncReport: Hashable, Sendable {
    public var added = 0
    public var updated = 0
    public var removed = 0
    /// Entries where a value changed here was kept in place of the new one.
    public var keptLocalChanges: [ConnectionsImport.Note] = []
    /// Entries of the file that the sync could not use.
    public var problems: [ConnectionsImport.Note] = []
    /// Commands that the sync did not keep.
    public var removedCommands: [ConnectionsImport.Note] = []
    /// Entries that the sync did not remove, because the file had problems.
    /// A bad entry could be one of them, so nothing is removed until the
    /// file is clean.
    public var removalsSkipped = 0

    public init() {}

    public var changedSomething: Bool { added + updated + removed > 0 }

    /// One line for the editor and the sidebar.
    public var summary: String {
        var parts: [String] = []
        if added > 0 { parts.append("\(added) added") }
        if updated > 0 { parts.append("\(updated) changed") }
        if removed > 0 { parts.append("\(removed) removed") }
        if parts.isEmpty { parts.append("No changes") }
        if !problems.isEmpty { parts.append("\(problems.count) entries left out") }
        if removalsSkipped > 0 { parts.append("\(removalsSkipped) not removed because of errors") }
        return parts.joined(separator: ", ")
    }
}
