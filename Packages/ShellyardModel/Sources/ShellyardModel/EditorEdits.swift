//
//  EditorEdits.swift
//  ShellyardModel
//

import Foundation

// The editor holds a draft of a node while the person types. A sync can
// change the same node while the editor is open. When the draft is saved,
// only the fields that the person changed in the draft are written, so the
// draft does not undo the sync. The place in the tree and the sync link
// never come from the draft.

private func take<Root, Value: Equatable>(
    _ keyPath: WritableKeyPath<Root, Value>,
    into result: inout Root,
    draft: Root,
    base: Root
) {
    if draft[keyPath: keyPath] != base[keyPath: keyPath] {
        result[keyPath: keyPath] = draft[keyPath: keyPath]
    }
}

extension NodeSettings {
    /// These settings, with each field that `draft` changed since `base`.
    public func applyingEdits(of draft: NodeSettings, since base: NodeSettings) -> NodeSettings {
        var result = self
        take(\.username, into: &result, draft: draft, base: base)
        take(\.authentication, into: &result, draft: draft, base: base)
        take(\.jumpHost, into: &result, draft: draft, base: base)
        take(\.colorTag, into: &result, draft: draft, base: base)
        take(\.agentForwarding, into: &result, draft: draft, base: base)
        take(\.compression, into: &result, draft: draft, base: base)
        take(\.keepAliveSeconds, into: &result, draft: draft, base: base)
        take(\.x11Forwarding, into: &result, draft: draft, base: base)
        take(\.hostKeyPolicy, into: &result, draft: draft, base: base)
        take(\.afterConnectText, into: &result, draft: draft, base: base)
        take(\.beforeConnect, into: &result, draft: draft, base: base)
        return result
    }
}

extension Connection {
    /// This connection, with each field that `draft` changed since `base`.
    public func applyingEdits(of draft: Connection, since base: Connection) -> Connection {
        var result = self
        take(\.name, into: &result, draft: draft, base: base)
        take(\.host, into: &result, draft: draft, base: base)
        take(\.port, into: &result, draft: draft, base: base)
        take(\.isFavorite, into: &result, draft: draft, base: base)
        take(\.forwards, into: &result, draft: draft, base: base)
        take(\.notes, into: &result, draft: draft, base: base)
        result.settings = settings.applyingEdits(of: draft.settings, since: base.settings)
        return result
    }
}

extension Folder {
    /// This folder, with each field that `draft` changed since `base`.
    public func applyingEdits(of draft: Folder, since base: Folder) -> Folder {
        var result = self
        take(\.name, into: &result, draft: draft, base: base)
        take(\.notes, into: &result, draft: draft, base: base)
        result.settings = settings.applyingEdits(of: draft.settings, since: base.settings)
        switch (base.sync, draft.sync) {
        case (nil, nil):
            break
        case (_, nil):
            result.sync = nil
        case let (nil, new?):
            result.sync = new
        case let (old?, new?):
            result.sync = (result.sync ?? old).applyingEdits(of: new, since: old)
        }
        return result
    }
}

extension FolderSync {
    /// This configuration, with each field that `draft` changed since `base`.
    public func applyingEdits(of draft: FolderSync, since base: FolderSync) -> FolderSync {
        var result = self
        take(\.url, into: &result, draft: draft, base: base)
        take(\.username, into: &result, draft: draft, base: base)
        take(\.password, into: &result, draft: draft, base: base)
        take(\.interval, into: &result, draft: draft, base: base)
        take(\.trustsServer, into: &result, draft: draft, base: base)
        take(\.excludedIDs, into: &result, draft: draft, base: base)
        return result
    }
}
