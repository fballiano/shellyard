//
//  SyncEngine.swift
//  ShellyardModel
//

import Foundation

extension Document {
    /// Makes the contents of a synced folder match a file.
    ///
    /// The rules:
    ///
    /// - An item is matched to a node by its `id`. An item without an `id`,
    ///   or with an `id` used twice, is left out.
    /// - A new `id` adds a node. A known `id` changes the node, field by
    ///   field: a field that the person changed here keeps their value, and
    ///   every other field takes the value of the file.
    /// - A synced node that the file no longer lists is removed. A node that
    ///   the person added is never changed or removed. When a removed folder
    ///   holds such a node, the node moves to the top of the synced folder.
    /// - The place and the order of each synced node follow the file. The
    ///   nodes that the person added come after them.
    /// - An `id` in `excludedIDs` is not added. A synced node that the person
    ///   moved out of the folder stops syncing, and its `id` is excluded.
    ///
    /// Nothing is removed while the file has a bad item, because the bad
    /// item could be one that still exists. A file with no usable item
    /// changes nothing when the folder has synced nodes: see
    /// `SyncError.wouldRemoveEverything`.
    ///
    /// The document is not changed when this throws.
    @discardableResult
    public mutating func applySync(_ file: ConnectionsFile, toFolder folderID: UUID) throws -> SyncReport {
        var engine = SyncEngine(document: self, rootID: folderID)
        let report = try engine.run(file)
        self = engine.document
        return report
    }

    /// Makes the nodes of a synced folder normal nodes, when the person
    /// turns its sync off. A later sync, from any address, then never
    /// removes them.
    public mutating func releaseSyncedNodes(of folderID: UUID) {
        for at in folders.indices where folders[at].syncLink?.sourceID == folderID {
            folders[at].syncLink = nil
        }
        for at in connections.indices where connections[at].syncLink?.sourceID == folderID {
            connections[at].syncLink = nil
        }
    }

    /// Records the synced nodes inside a node that is about to be deleted,
    /// so that the next sync does not add them again.
    public mutating func excludeFromSync(nodesIn id: UUID) {
        let index = DocumentIndex(self)
        func isInside(_ parentID: UUID?, _ selfID: UUID) -> Bool {
            selfID == id || parentID.map { index.isDescendant($0, ofOrEqualTo: id) } == true
        }
        var links: [SyncLink] = []
        links += folders.filter { isInside($0.parentID, $0.id) }.compactMap(\.syncLink)
        links += connections.filter { isInside($0.parentID, $0.id) }.compactMap(\.syncLink)
        for link in links {
            guard let at = folders.firstIndex(where: { $0.id == link.sourceID }),
                  folders[at].sync != nil,
                  !folders[at].sync!.excludedIDs.contains(link.externalID) else { continue }
            folders[at].sync!.excludedIDs.append(link.externalID)
        }
    }
}

extension Document {
    /// Makes each synced node that left its synced folder a normal node.
    ///
    /// A node leaves when the person moves it out, when the synced folder is
    /// deleted, or when its sync is off. Without this, the node keeps a link
    /// that no sync clears, and it cannot become a synced folder itself. A
    /// node that the person moved out is excluded, so the sync does not add
    /// it again. The sync does the same at its next run; this does it at once.
    public mutating func releaseDetachedSyncedNodes() {
        guard folders.contains(where: { $0.syncLink != nil })
            || connections.contains(where: { $0.syncLink != nil }) else { return }
        let index = DocumentIndex(self)
        var exclusions: [UUID: [String]] = [:]

        /// False when the node must lose its link.
        func staysLinked(_ link: SyncLink, id: UUID, parentID: UUID?) -> Bool {
            guard id != link.sourceID, index.folder(link.sourceID)?.sync != nil else { return false }
            // A parent that no longer exists is not a move by the person:
            // the next sync places the node again.
            if let parentID, index.folder(parentID) == nil
                || index.isDescendant(parentID, ofOrEqualTo: link.sourceID) {
                return true
            }
            exclusions[link.sourceID, default: []].append(link.externalID)
            return false
        }

        for at in folders.indices {
            guard let link = folders[at].syncLink,
                  !staysLinked(link, id: folders[at].id, parentID: folders[at].parentID) else { continue }
            folders[at].syncLink = nil
        }
        for at in connections.indices {
            guard let link = connections[at].syncLink,
                  !staysLinked(link, id: connections[at].id, parentID: connections[at].parentID) else { continue }
            connections[at].syncLink = nil
        }
        for (sourceID, externalIDs) in exclusions {
            guard let at = folders.firstIndex(where: { $0.id == sourceID }),
                  var sync = folders[at].sync else { continue }
            for externalID in externalIDs where !sync.excludedIDs.contains(externalID) {
                sync.excludedIDs.append(externalID)
            }
            folders[at].sync = sync
        }
    }
}

/// The work of one sync, on a copy of the document.
struct SyncEngine {
    private(set) var document: Document
    let rootID: UUID

    private var report = SyncReport()
    private var config = FolderSync()
    private var excluded: Set<String> = []
    private var existingFolders: [String: UUID] = [:]
    private var existingConnections: [String: UUID] = [:]
    private var seenIDs: Set<String> = []
    private var keptNodes: Set<UUID> = []
    private var hadProblems = false
    /// True when the file lists at least one usable item, excluded or not.
    private var listedAnything = false
    /// The synced children of each parent, in the order of the file.
    private var syncedOrder: [UUID: [UUID]] = [:]
    /// For each node that the person added, its folder and the synced nodes
    /// above it in that folder before the sync, nearest last.
    private var localPlaces: [UUID: (parent: UUID, syncedAbove: [UUID])] = [:]

    init(document: Document, rootID: UUID) {
        self.document = document
        self.rootID = rootID
    }

    mutating func run(_ file: ConnectionsFile) throws -> SyncReport {
        guard let root = document.folders.first(where: { $0.id == rootID }) else {
            throw SyncError.folderNotFound
        }
        guard let sync = root.sync else { throw SyncError.notSynced }
        config = sync
        excluded = Set(sync.excludedIDs)

        collectExistingNodes()
        rememberLocalPlaces()
        let existingCount = existingFolders.count + existingConnections.count

        if let reason = file.settingsProblem {
            problem([root.name], "the settings of the list: \(reason)")
        }
        walk(file.items, parent: rootID, path: [], depth: 0)

        if !listedAnything, existingCount > 0, !hadProblems {
            throw SyncError.wouldRemoveEverything(existingCount)
        }
        removeNodesNoLongerListed()
        renumber()
        if file.settingsProblem == nil {
            applyRootSettings(file.settings)
        }

        if let at = document.folders.firstIndex(where: { $0.id == rootID }) {
            document.folders[at].sync = config
        }
        return report
    }

    // MARK: - The nodes that came from this folder before

    /// Finds the synced nodes of this folder. A node outside the folder was
    /// moved out by the person: it stops syncing, and its id is excluded.
    private mutating func collectExistingNodes() {
        let index = DocumentIndex(document)
        /// Inside the synced folder, or lost: a parent that no longer exists
        /// is not a move by the person, so the sync places the node again.
        func isInside(_ parentID: UUID?) -> Bool {
            guard let parentID else { return false }
            return index.folder(parentID) == nil || index.isDescendant(parentID, ofOrEqualTo: rootID)
        }

        for at in document.folders.indices {
            guard let link = document.folders[at].syncLink, link.sourceID == rootID else { continue }
            let folder = document.folders[at]
            if folder.id != rootID, isInside(folder.parentID), existingFolders[link.externalID] == nil {
                existingFolders[link.externalID] = folder.id
            } else {
                document.folders[at].syncLink = nil
                if !isInside(folder.parentID) { exclude(link.externalID) }
            }
        }
        for at in document.connections.indices {
            guard let link = document.connections[at].syncLink, link.sourceID == rootID else { continue }
            let connection = document.connections[at]
            if isInside(connection.parentID), existingConnections[link.externalID] == nil {
                existingConnections[link.externalID] = connection.id
            } else {
                document.connections[at].syncLink = nil
                if !isInside(connection.parentID) { exclude(link.externalID) }
            }
        }
    }

    private mutating func exclude(_ externalID: String) {
        guard excluded.insert(externalID).inserted else { return }
        config.excludedIDs.append(externalID)
    }

    // MARK: - Adding and changing

    private mutating func walk(_ items: [ConnectionsFile.Item], parent: UUID, path: [String], depth: Int) {
        guard depth < Document.maximumDepth else {
            if !items.isEmpty { problem(path, "the list is nested too deep.") }
            return
        }
        for (offset, item) in items.enumerated() {
            switch item {
            case let .invalid(name, reason):
                problem(path + [name ?? "Entry \(offset + 1)"], reason)
            case let .folder(remote, externalID, children):
                let here = path + [remote.name]
                switch accept(externalID, at: here) {
                case .skip:
                    continue
                case .excluded:
                    // The person deleted this folder, not what is in it. The
                    // children that are still listed take its place.
                    walk(children, parent: parent, path: here, depth: depth + 1)
                case let .use(externalID):
                    let id = place(folder: remote, externalID: externalID, under: parent, path: here)
                    walk(children, parent: id, path: here, depth: depth + 1)
                }
            case let .connection(remote, externalID):
                let here = path + [remote.name]
                guard case let .use(externalID) = accept(externalID, at: here) else { continue }
                place(connection: remote, externalID: externalID, under: parent, path: here)
            }
        }
    }

    private enum Acceptance {
        /// A bad item: it and everything in it are left out.
        case skip
        /// The person removed this item. Its children are still read.
        case excluded
        case use(String)
    }

    /// What the sync does with the id of an item.
    private mutating func accept(_ externalID: String?, at path: [String]) -> Acceptance {
        guard let externalID, !externalID.trimmingCharacters(in: .whitespaces).isEmpty else {
            problem(path, "it has no id, so the sync cannot follow it.")
            return .skip
        }
        guard seenIDs.insert(externalID).inserted else {
            problem(path, "the id \"\(externalID)\" is used two times.")
            return .skip
        }
        listedAnything = true
        return excluded.contains(externalID) ? .excluded : .use(externalID)
    }

    @discardableResult
    private mutating func place(folder remote: Folder, externalID: String, under parent: UUID,
                                path: [String]) -> UUID {
        var incoming = SyncedFields(folder: remote)
        incoming.settings = filterUntrusted(incoming.settings, at: path)
        let link = SyncLink(sourceID: rootID, externalID: externalID, base: incoming)

        if let id = existingFolders[externalID],
           let at = document.folders.firstIndex(where: { $0.id == id }) {
            let before = document.folders[at]
            var merged = merge(local: SyncedFields(folder: before),
                               base: before.syncLink?.base ?? incoming, remote: incoming, path: path)
            merged.host = ""
            var after = before
            after.name = merged.name
            after.settings = merged.settings
            after.notes = merged.notes
            after.parentID = parent
            after.syncLink = link
            document.folders[at] = after
            count(before: SyncedFields(folder: before), after: SyncedFields(folder: after),
                  moved: before.parentID != parent)
            keptNodes.insert(id)
            syncedOrder[parent, default: []].append(id)
            return id
        }

        let folder = Folder(parentID: parent, name: incoming.name, settings: incoming.settings,
                            notes: incoming.notes, syncLink: link)
        document.folders.append(folder)
        report.added += 1
        keptNodes.insert(folder.id)
        syncedOrder[parent, default: []].append(folder.id)
        return folder.id
    }

    private mutating func place(connection remote: Connection, externalID: String, under parent: UUID,
                                path: [String]) {
        var incoming = SyncedFields(connection: remote)
        incoming.settings = filterUntrusted(incoming.settings, at: path)
        let link = SyncLink(sourceID: rootID, externalID: externalID, base: incoming)

        if let id = existingConnections[externalID],
           let at = document.connections.firstIndex(where: { $0.id == id }) {
            let before = document.connections[at]
            let merged = merge(local: SyncedFields(connection: before),
                               base: before.syncLink?.base ?? incoming, remote: incoming, path: path)
            var after = before
            after.name = merged.name
            after.host = merged.host
            after.port = merged.port
            after.isFavorite = merged.isFavorite
            after.settings = merged.settings
            after.forwards = merged.forwards
            after.notes = merged.notes
            after.parentID = parent
            after.syncLink = link
            document.connections[at] = after
            count(before: SyncedFields(connection: before), after: SyncedFields(connection: after),
                  moved: before.parentID != parent)
            keptNodes.insert(id)
            syncedOrder[parent, default: []].append(id)
            return
        }

        let connection = Connection(
            parentID: parent, name: incoming.name, host: incoming.host, port: incoming.port,
            isFavorite: incoming.isFavorite, settings: incoming.settings,
            forwards: incoming.forwards.map { forward in
                var fresh = forward
                fresh.id = UUID()
                return fresh
            },
            notes: incoming.notes, syncLink: link
        )
        document.connections.append(connection)
        report.added += 1
        keptNodes.insert(connection.id)
        syncedOrder[parent, default: []].append(connection.id)
    }

    /// Gives the synced folder the top-level settings of the list. A
    /// setting that the person changed keeps their value. A setting that the
    /// list never sent, such as the authentication, stays as the person set it.
    private mutating func applyRootSettings(_ settings: NodeSettings) {
        guard let at = document.folders.firstIndex(where: { $0.id == rootID }) else { return }
        let remote = filterUntrusted(settings, at: [document.folders[at].name])
        let local = document.folders[at].settings
        let merged = mergeSettings(local: local, base: config.settingsBase, remote: remote)
        if merged != local {
            document.folders[at].settings = merged
            report.updated += 1
        }
        config.settingsBase = remote
    }

    private mutating func count(before: SyncedFields, after: SyncedFields, moved: Bool) {
        if moved || !sameContent(before, after) { report.updated += 1 }
    }

    /// Removes what a server must not set unless the person trusts it: a
    /// command that runs on this Mac, and the forwarding of the SSH agent
    /// or of X11, which give the far host a way back to this Mac.
    private mutating func filterUntrusted(_ settings: NodeSettings, at path: [String]) -> NodeSettings {
        var result = settings
        if !config.trustsServer {
            if result.agentForwarding == .value(true) {
                result.agentForwarding = .inherit
                note(&report.removedCommands, path,
                     "Agent forwarding — removed, because this server is not trusted.")
            }
            if result.x11Forwarding == .value(true) {
                result.x11Forwarding = .inherit
                note(&report.removedCommands, path,
                     "X11 forwarding — removed, because this server is not trusted.")
            }
        }
        guard let command = settings.beforeConnect.ownValue, !command.isEmpty else { return result }
        let line = [command.launchPath, command.arguments].filter { !$0.isEmpty }.joined(separator: " ")
        if CommandPlaceholders.containsSecretMark(line) {
            result.beforeConnect = .inherit
            note(&report.removedCommands, path,
                 "\(line) — removed, because it puts a password on a command line.")
        } else if !config.trustsServer {
            result.beforeConnect = .inherit
            note(&report.removedCommands, path,
                 "\(line) — removed, because this server is not trusted.")
        }
        return result
    }

    // MARK: - The merge

    /// Three-way merge: a field that still has its base value takes the
    /// remote value; a field that was changed here keeps the local value.
    private mutating func merge(local: SyncedFields, base: SyncedFields, remote: SyncedFields,
                                path: [String]) -> SyncedFields {
        func pick<Value: Equatable>(_ keyPath: KeyPath<SyncedFields, Value>) -> Value {
            local[keyPath: keyPath] == base[keyPath: keyPath]
                ? remote[keyPath: keyPath] : local[keyPath: keyPath]
        }
        var result = local
        result.name = pick(\.name)
        result.host = pick(\.host)
        result.port = pick(\.port)
        result.isFavorite = pick(\.isFavorite)
        result.notes = pick(\.notes)
        result.settings = mergeSettings(local: local.settings, base: base.settings, remote: remote.settings)
        if Self.sameForwards(local.forwards, remote.forwards) {
            result.forwards = local.forwards
        } else if Self.sameForwards(local.forwards, base.forwards) {
            result.forwards = remote.forwards.map { forward in
                var fresh = forward
                fresh.id = UUID()
                return fresh
            }
        }
        if !sameContent(result, remote) {
            note(&report.keptLocalChanges, path, "Your changes stay.")
        }
        return result
    }

    private func mergeSettings(local: NodeSettings, base: NodeSettings, remote: NodeSettings) -> NodeSettings {
        var result = local
        func pick<Value>(_ keyPath: WritableKeyPath<NodeSettings, Inherited<Value>>) {
            if local[keyPath: keyPath] == base[keyPath: keyPath] {
                result[keyPath: keyPath] = remote[keyPath: keyPath]
            }
        }
        pick(\.username)
        pick(\.jumpHost)
        pick(\.colorTag)
        pick(\.agentForwarding)
        pick(\.compression)
        pick(\.keepAliveSeconds)
        pick(\.x11Forwarding)
        pick(\.hostKeyPolicy)
        pick(\.afterConnectText)
        pick(\.beforeConnect)
        result.authentication = Self.mergeAuthentication(
            local: local.authentication, base: base.authentication, remote: remote.authentication
        )
        return result
    }

    /// The method and the key path merge as one field, and the secret as
    /// another. A password typed here therefore stays when the file sends
    /// none, and a new password from the file arrives when none was typed.
    static func mergeAuthentication(
        local: Inherited<Authentication>,
        base: Inherited<Authentication>,
        remote: Inherited<Authentication>
    ) -> Inherited<Authentication> {
        func method(_ value: Inherited<Authentication>) -> Inherited<Authentication> {
            var settings = NodeSettings(authentication: value)
            settings.removeSecrets()
            return settings.authentication
        }
        func secret(_ value: Inherited<Authentication>) -> Secret {
            value.ownValue?.secret ?? .empty
        }
        /// Two methods that take the same secret: both a password, or both
        /// the same key file.
        func sameKind(_ left: Inherited<Authentication>, _ right: Inherited<Authentication>) -> Bool {
            switch (left, right) {
            case (.value(.password), .value(.password)): true
            case let (.value(.privateKey(leftPath, _)), .value(.privateKey(rightPath, _))):
                leftPath == rightPath
            default: false
            }
        }
        let chosenMethod = method(local) == method(base) ? method(remote) : method(local)
        // A secret never moves to another method: a password typed here must
        // not become the passphrase of a key, or the other way round.
        let chosenSecret: Secret = switch (sameKind(chosenMethod, local), sameKind(chosenMethod, remote)) {
        case (true, true): secret(local) == secret(base) ? secret(remote) : secret(local)
        case (true, false): secret(local)
        case (false, true): secret(remote)
        case (false, false): .empty
        }
        switch chosenMethod {
        case .value(.password):
            return .value(.password(chosenSecret))
        case let .value(.privateKey(path, _)):
            return .value(.privateKey(path: path, passphrase: chosenSecret))
        default:
            return chosenMethod
        }
    }

    /// Two lists of tunnels with the same content. The identifiers differ
    /// at each read of the file, so they do not count.
    static func sameForwards(_ left: [PortForward], _ right: [PortForward]) -> Bool {
        func strip(_ list: [PortForward]) -> [PortForward] {
            list.map { forward in
                var copy = forward
                copy.id = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
                return copy
            }
        }
        return strip(left) == strip(right)
    }

    private func sameContent(_ left: SyncedFields, _ right: SyncedFields) -> Bool {
        var left = left
        var right = right
        guard Self.sameForwards(left.forwards, right.forwards) else { return false }
        left.forwards = []
        right.forwards = []
        return left == right
    }

    // MARK: - Removing

    private mutating func removeNodesNoLongerListed() {
        let goneFolders = Set(existingFolders.values).subtracting(keptNodes)
        let goneConnections = Set(existingConnections.values).subtracting(keptNodes)
        let goneCount = goneFolders.count + goneConnections.count
        guard goneCount > 0 else { return }
        guard !hadProblems else {
            report.removalsSkipped = goneCount
            return
        }

        // A node that the person added, inside a folder that goes, moves to
        // the top of the synced folder rather than going with it.
        for at in document.folders.indices
        where !goneFolders.contains(document.folders[at].id)
            && document.folders[at].parentID.map(goneFolders.contains) == true {
            document.folders[at].parentID = rootID
            document.folders[at].position = Int.max / 2
        }
        for at in document.connections.indices
        where !goneConnections.contains(document.connections[at].id)
            && document.connections[at].parentID.map(goneFolders.contains) == true {
            document.connections[at].parentID = rootID
            document.connections[at].position = Int.max / 2
        }
        document.folders.removeAll { goneFolders.contains($0.id) }
        document.connections.removeAll { goneConnections.contains($0.id) }
        report.removed = goneCount
    }

    // MARK: - Order

    /// Notes where the person put their own nodes among the synced ones.
    private mutating func rememberLocalPlaces() {
        let index = DocumentIndex(document)
        let synced = Set(existingFolders.values).union(existingConnections.values)
        for parent in [rootID] + Array(existingFolders.values) {
            var syncedAbove: [UUID] = []
            for child in index.children(of: parent).map(\.id) {
                if synced.contains(child) {
                    syncedAbove.append(child)
                } else {
                    localPlaces[child] = (parent, syncedAbove)
                }
            }
        }
    }

    /// In each parent that the sync filled: the synced nodes in the order of
    /// the file. A node that the person added stays below the same synced
    /// node as before; when that node is gone, below the nearest one above
    /// it that is still there. A node above every synced node stays at the
    /// top. A node that is new in this folder goes to the end.
    private mutating func renumber() {
        let index = DocumentIndex(document)
        var parents = Set(syncedOrder.keys)
        parents.insert(rootID)
        for parent in parents {
            let synced = syncedOrder[parent] ?? []
            let syncedSet = Set(synced)
            var atTop: [UUID] = []
            var below: [UUID: [UUID]] = [:]
            var atEnd: [UUID] = []
            for id in index.children(of: parent).map(\.id) where !syncedSet.contains(id) {
                guard let place = localPlaces[id], place.parent == parent else {
                    atEnd.append(id)
                    continue
                }
                if let anchor = place.syncedAbove.last(where: syncedSet.contains) {
                    below[anchor, default: []].append(id)
                } else {
                    atTop.append(id)
                }
            }
            let order = atTop + synced.flatMap { [$0] + (below[$0] ?? []) } + atEnd
            for (position, id) in order.enumerated() {
                if let at = document.folders.firstIndex(where: { $0.id == id }) {
                    document.folders[at].position = position
                } else if let at = document.connections.firstIndex(where: { $0.id == id }) {
                    document.connections[at].position = position
                }
            }
        }
    }

    // MARK: - Notes

    private mutating func problem(_ path: [String], _ text: String) {
        hadProblems = true
        note(&report.problems, path, text)
    }

    private func note(_ list: inout [ConnectionsImport.Note], _ path: [String], _ text: String) {
        list.append(ConnectionsImport.Note(path: path.joined(separator: " / "), text: text))
    }
}
