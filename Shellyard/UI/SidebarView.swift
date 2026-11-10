//
//  SidebarView.swift
//  Shellyard
//

import SwiftUI
import ShellyardModel

/// The bookmark tree.
///
/// A double click on a connection opens it. A right click offers everything
/// else, including the editor, which appears as a sheet rather than a panel
/// that takes room from the terminal.
struct SidebarView: View {
    @EnvironmentObject private var store: DocumentStore
    @EnvironmentObject private var sessions: SessionsController
    @State private var isTopLevelTarget = false
    @State private var dropMark: SidebarDropMark?

    var body: some View {
        // The local shell sits above the filter: it is not a bookmark, so
        // the filter does not find it and must not hide it. `.searchable`
        // is not used, because the system then draws its field above
        // everything else in the column.
        VStack(spacing: 0) {
            LocalShellButton()
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
            Divider()
            FilterField(text: $store.filterText)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
            tree
        }
        .alert(
            store.deletingID.flatMap { store.deletionQuestion(for: $0)?.title } ?? "Delete?",
            isPresented: Binding(
                get: { store.deletingID != nil },
                set: { if !$0 { store.deletingID = nil } }
            )
        ) {
            Button("Delete", role: .destructive) { store.confirmDeletion() }
            Button("Cancel", role: .cancel) { store.deletingID = nil }
        } message: {
            Text(store.deletingID.flatMap { store.deletionQuestion(for: $0)?.detail } ?? "")
        }
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 2) {
                Button { store.addConnection() } label: {
                    Label("New connection", systemImage: "plus")
                }
                .help("New connection")

                Button { store.addFolder() } label: {
                    Label("New folder", systemImage: "folder.badge.plus")
                }
                .help("New folder")

                Spacer()

                // The name of the document lives here, not in the title bar.
                //
                // There is no delete button beside the add buttons: a slip
                // there opens a destructive dialog. Delete lives in the
                // context menu of the row.
                if let name = store.documentURL?.deletingPathExtension().lastPathComponent {
                    Text(name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(store.documentURL?.path ?? "")
                }
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.bar)
        }
    }
}

private extension SidebarView {
    /// The bookmark tree.
    ///
    /// A `List` is not used here. On a Mac it draws sidebar rows far apart,
    /// and neither `listRowInsets` nor a row height changes that. A stack
    /// draws exactly the height each row asks for.
    var tree: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(store.visibleRows()) { row in
                    SidebarRow(row: row, mark: $dropMark)
                }

                // The space under the last row takes a drop too, so a node can
                // be moved out of every folder and back to the top level.
                Color.clear
                    .frame(maxWidth: .infinity, minHeight: 40)
                    .contentShape(Rectangle())
                    .onDrop(
                        of: [.shellyardNode],
                        delegate: TopLevelDropDelegate(
                            store: store,
                            isTargeted: $isTopLevelTarget,
                            mark: $dropMark
                        )
                    )
                    .background(
                        RoundedRectangle(cornerRadius: 5)
                            .strokeBorder(isTopLevelTarget ? Color.accentColor : .clear)
                            .padding(.horizontal, 2)
                    )
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// The filter over the bookmark tree.
///
/// It does what the system search field did: a clear button while it holds
/// text, and Escape empties it.
private struct FilterField: View {
    @Binding var text: String
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Filter", text: $text)
                .textFieldStyle(.plain)
                .focused($isFocused)
                .onExitCommand { text = "" }
                .accessibilityIdentifier("sidebar-filter")
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Clear the filter")
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
        .glassEffect(.regular, in: Capsule())
        .contentShape(Capsule())
        .onTapGesture { isFocused = true }
    }
}

/// Opens a shell on this Mac, in a new tab.
///
/// A row of its own above the filter, with a divider under it: it is not a
/// bookmark, so one click opens it, and there is nothing to select or edit.
///
/// The row is marked while a local shell tab is in front and no bookmark is
/// chosen, the same way a bookmark row is marked for its own tab.
private struct LocalShellButton: View {
    @EnvironmentObject private var store: DocumentStore
    @EnvironmentObject private var sessions: SessionsController
    @State private var isHovering = false

    private var isMarked: Bool {
        sessions.selectedTab?.isLocal == true && store.selection == nil
    }

    private var rowFill: AnyShapeStyle {
        if isMarked { return AnyShapeStyle(Color.accentColor) }
        if isHovering { return AnyShapeStyle(.quaternary) }
        return AnyShapeStyle(Color.clear)
    }

    var body: some View {
        Button { sessions.openLocal() } label: {
            HStack(spacing: 6) {
                Image(systemName: "laptopcomputer")
                    .foregroundStyle(isMarked ? AnyShapeStyle(Color.white) : AnyShapeStyle(.tint))
                    .frame(width: 18)
                Text("Local Shell")
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text("⇧⌘T")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(isMarked ? AnyShapeStyle(Color.white.opacity(0.8))
                                              : AnyShapeStyle(.secondary))
            }
            .foregroundStyle(isMarked ? Color.white : Color.primary)
            .padding(.horizontal, 8)
            .frame(height: 28)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 6).fill(rowFill)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help("Open a shell on this Mac in a new tab")
        .accessibilityIdentifier("local-shell")
    }
}

/// One row of the sidebar.
///
/// The tree is drawn flat, with the depth as leading space. A nested
/// `DisclosureGroup` would decide the row height itself, and the rows would
/// stand far apart.
private struct SidebarRow: View {
    @EnvironmentObject private var store: DocumentStore
    @EnvironmentObject private var sessions: SessionsController
    @EnvironmentObject private var transfer: TransferController
    @EnvironmentObject private var syncer: SyncController
    let row: DocumentStore.Row
    @Binding var mark: SidebarDropMark?
    @State private var isHovering = false

    /// How much a level of the tree moves a row to the right.
    private static let indent: CGFloat = 14
    /// The height of every row.
    private static let height: CGFloat = 24

    private var isSelected: Bool { store.selection == row.id }

    private var rowFill: AnyShapeStyle {
        if isSelected { return AnyShapeStyle(Color.accentColor) }
        if isHovering { return AnyShapeStyle(.quaternary) }
        return AnyShapeStyle(Color.clear)
    }

    /// Where the mark sits for this row, if a drag is over it.
    ///
    /// Nothing is drawn once the drag has ended, whatever is left in `mark`.
    private var placement: DropPlacement? {
        guard store.draggingID != nil, mark?.rowID == row.id else { return nil }
        return mark?.placement
    }

    var body: some View {
        HStack(spacing: 4) {
            Color.clear.frame(width: CGFloat(row.depth) * Self.indent, height: 1)
            content
        }
        .frame(height: Self.height)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(rowFill)
        )
        // The row under the pointer is marked, the same way as the local
        // shell row, so it is clear what a click will hit.
        .onHover { isHovering = $0 }
        .foregroundStyle(isSelected ? Color.white : Color.primary)
        .overlay(alignment: .top) { if placement == .before { insertionLine } }
        .overlay(alignment: .bottom) { if placement == .after { insertionLine } }
        .overlay {
            if placement == .inside {
                RoundedRectangle(cornerRadius: 5)
                    .strokeBorder(Color.accentColor, lineWidth: 2)
            }
        }
        // A drag moves a bookmark or a whole folder.
        .onDrag {
            sidebarDragProvider(for: row.id, store: store)
        } preview: {
            Label(row.node.name, systemImage: row.node.isFolder ? "folder" : "terminal")
                .padding(6)
        }
        .onDrop(
            of: [.shellyardNode],
            delegate: SidebarDropDelegate(
                row: row, height: Self.height, store: store, mark: $mark
            )
        )
    }

    /// Shows exactly where the dragged node will land.
    ///
    /// A line above or below means "beside this row". A ring around a folder
    /// means "inside this folder".
    private var insertionLine: some View {
        HStack(spacing: 0) {
            // The line starts where the row's own name starts, so the level
            // it lands at is plain to see.
            Color.clear.frame(width: CGFloat(row.depth) * Self.indent + 16)
            Capsule().fill(Color.accentColor).frame(height: 2)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch row.node {
        case let .folder(folder):
            Button {
                store.setExpanded(folder, !store.isExpanded(folder))
            } label: {
                Image(systemName: store.isExpanded(folder)
                      ? "chevron.down" : "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 12)
            }
            .buttonStyle(.plain)

            HStack(spacing: 4) {
                rowLabel(
                    folder.name,
                    icon: "folder",
                    tint: tint(of: folder.settings.colorTag.ownValue),
                    isFavorite: false
                )
                if folder.sync != nil { syncMark(folder) }
            }
            .contentShape(Rectangle())
            .simultaneousGesture(TapGesture(count: 1).onEnded {
                store.selection = folder.id
            })
            .simultaneousGesture(TapGesture(count: 2).onEnded {
                store.selection = folder.id
                store.setExpanded(folder, !store.isExpanded(folder))
            })
            .contextMenu { folderMenu(folder) }

        case let .connection(connection):
            // A connection has no children, so the space a chevron would take
            // is left empty. The names then line up under the folder name.
            Color.clear.frame(width: 12, height: 1)

            rowLabel(
                connection.name,
                icon: "terminal",
                tint: tint(of: store.index.effectiveSettings(for: connection).colorTag),
                isFavorite: connection.isFavorite,
                activity: sessions.activity(for: connection.id)
            )
            .contentShape(Rectangle())
            // A double click connects, the way a double click opens a file.
            // The single click is handled too: a double-click gesture on its
            // own swallows the first click, and the row would never be chosen.
            .simultaneousGesture(TapGesture(count: 1).onEnded {
                store.selection = connection.id
            })
            .simultaneousGesture(TapGesture(count: 2).onEnded {
                store.selection = connection.id
                sessions.open(connection: connection)
            })
            .contextMenu { connectionMenu(connection) }
        }
    }

    /// The state of a synced folder: running, failed, or quiet.
    @ViewBuilder
    private func syncMark(_ folder: Folder) -> some View {
        if syncer.isRunning(folder.id) {
            ProgressView().controlSize(.mini)
                .help("Syncing")
        } else if let status = syncer.status(of: folder.id), status.failed {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 9))
                .foregroundStyle(.orange)
                .help("The last sync failed: \(status.message)")
        } else {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .help(syncer.status(of: folder.id)?.message ?? "Synced from a web address")
        }
    }

    private func rowLabel(
        _ name: String, icon: String, tint: Color, isFavorite: Bool,
        activity: SessionsController.ConnectionActivity = .none
    ) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(tint)
                .frame(width: 15)
            Text(name)
                .lineLimit(1)
            if isFavorite {
                Image(systemName: "star.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(.yellow)
            }
            Spacer(minLength: 0)
            // The tree doubles as a status board: a dot on every connection
            // that has a session open right now.
            switch activity {
            case .none:
                EmptyView()
            case .connecting:
                Circle().fill(.orange).frame(width: 6, height: 6)
                    .help("Connecting")
            case .live:
                Circle().fill(.green).frame(width: 6, height: 6)
                    .help("Connected")
            }
        }
    }

    @ViewBuilder
    private func connectionMenu(_ connection: Connection) -> some View {
        Button("Connect") {
            store.selection = connection.id
            sessions.open(connection: connection)
        }
        Button("Browse Files") {
            store.selection = connection.id
            sessions.openFiles(connection: connection)
        }
        Divider()
        Button("Edit…") {
            store.selection = connection.id
            store.editingID = connection.id
        }
        Button("Duplicate") { store.duplicate(connectionID: connection.id) }
        Button("Export…") { transfer.export(connection.id) }
        Divider()
        Button("Delete…", role: .destructive) { store.deletingID = connection.id }
    }

    @ViewBuilder
    private func folderMenu(_ folder: Folder) -> some View {
        Button("Edit…") {
            store.selection = folder.id
            store.editingID = folder.id
        }
        Divider()
        Button("New Connection Here") {
            let connection = Connection(parentID: folder.id, name: "New Connection", host: "")
            store.update { $0.add(connection) }
            store.selection = connection.id
            store.editingID = connection.id
        }
        Button("New Folder Here") {
            let child = Folder(parentID: folder.id, name: "New Folder")
            store.update { $0.add(child) }
            store.selection = child.id
            store.editingID = child.id
        }
        if folder.sync != nil {
            Button("Sync Now") { Task { await syncer.syncNow(folder.id) } }
                .disabled(syncer.isRunning(folder.id) || folder.sync?.validURL == nil)
        }
        Divider()
        Button("Export…") { transfer.export(folder.id) }
        Divider()
        Button("Delete…", role: .destructive) { store.deletingID = folder.id }
    }


    private func tint(of tag: ColorTag?) -> Color {
        switch tag ?? .none {
        case .none: .secondary
        case .red: .red
        case .orange: .orange
        case .yellow: .yellow
        case .green: .green
        case .blue: .blue
        case .purple: .purple
        case .grey: .gray
        }
    }
}
