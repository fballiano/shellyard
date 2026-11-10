//
//  OpenConnectionPanel.swift
//  Shellyard
//

import SwiftUI
import ShellyardModel

/// The Open Connection field (⌘O): find a bookmark by name, host, or folder,
/// or type `user@host` to connect with no bookmark.
///
/// Return opens a terminal, ⌘Return opens the file browser, and Escape or a
/// click outside closes the field.
struct OpenConnectionPanel: View {
    @EnvironmentObject private var store: DocumentStore
    @EnvironmentObject private var sessions: SessionsController

    @State private var query = ""
    @State private var selectedRowID: String?
    @FocusState private var isFieldFocused: Bool

    /// One line of the list.
    enum Row: Identifiable {
        case bookmark(BookmarkSearch.Match)
        case quick(QuickConnectAddress)

        var id: String {
            switch self {
            case let .bookmark(match): match.id.uuidString
            case .quick: "quick"
            }
        }
    }

    /// The bookmarks first, then the typed address. An address with a user
    /// name is plainly not a bookmark name, so it goes first.
    private var rows: [Row] {
        let matches = BookmarkSearch.matches(for: query, in: store.index).map(Row.bookmark)
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, let address = QuickConnectAddress(trimmed) else { return matches }
        if trimmed.contains("@") || matches.isEmpty {
            return [.quick(address)] + matches
        }
        return matches + [.quick(address)]
    }

    var body: some View {
        let rows = rows
        ZStack(alignment: .top) {
            // A click anywhere else closes the field, the way Spotlight does.
            Color.black.opacity(0.08)
                .contentShape(Rectangle())
                .onTapGesture { close() }
                .accessibilityHidden(true)

            VStack(spacing: 0) {
                field(rows: rows)
                if !rows.isEmpty {
                    Divider()
                    list(rows: rows)
                }
            }
            .frame(width: 560)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.separator))
            .shadow(color: .black.opacity(0.25), radius: 20, y: 8)
            .padding(.top, 60)
        }
        .onAppear { selectedRowID = rows.first?.id }
        .task {
            // A terminal pane or the sidebar holds the keyboard, and a
            // focus request made while it does is lost. The window lets go
            // first, then the field asks until it has the keyboard.
            NSApp.keyWindow?.makeFirstResponder(nil)
            for _ in 0..<20 where !isFieldFocused {
                isFieldFocused = true
                try? await Task.sleep(for: .milliseconds(25))
            }
        }
        .onChange(of: query) {
            selectedRowID = self.rows.first?.id
        }
    }

    private func field(rows: [Row]) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Bookmark, host, or user@host", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 18))
                .focused($isFieldFocused)
                .accessibilityIdentifier("open-connection-field")
                .onSubmit { openSelected(in: rows, kind: .terminal) }
                .onKeyPress(.downArrow) {
                    move(by: 1, in: rows)
                    return .handled
                }
                .onKeyPress(.upArrow) {
                    move(by: -1, in: rows)
                    return .handled
                }
                .onKeyPress(.escape) {
                    close()
                    return .handled
                }
                // The menu gives ⌘Return to Connect, and the menu sees key
                // equivalents first. The menu item is turned off while this
                // field is open, so the key reaches the field.
                .onKeyPress(.return, phases: .down) { press in
                    guard press.modifiers.contains(.command) else { return .ignored }
                    openSelected(in: rows, kind: .files)
                    return .handled
                }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private func list(rows: [Row]) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(rows) { row in
                        RowView(row: row, isSelected: row.id == selectedRowID)
                            .id(row.id)
                            .contentShape(Rectangle())
                            .onTapGesture { open(row, kind: .terminal) }
                    }
                }
                .padding(6)
            }
            .frame(maxHeight: 340)
            .fixedSize(horizontal: false, vertical: true)
            .onChange(of: selectedRowID) {
                if let selectedRowID { proxy.scrollTo(selectedRowID) }
            }
        }
    }

    // MARK: - Actions

    private func move(by offset: Int, in rows: [Row]) {
        guard !rows.isEmpty else { return }
        let current = rows.firstIndex { $0.id == selectedRowID } ?? 0
        let next = min(max(current + offset, 0), rows.count - 1)
        selectedRowID = rows[next].id
    }

    private func openSelected(in rows: [Row], kind: TerminalTab.Kind) {
        guard let row = rows.first(where: { $0.id == selectedRowID }) ?? rows.first else { return }
        open(row, kind: kind)
    }

    private func open(_ row: Row, kind: TerminalTab.Kind) {
        sessions.showsOpenPanel = false
        switch row {
        case let .bookmark(match):
            sessions.open(connection: match.connection, kind: kind)
        case let .quick(address):
            sessions.openQuick(address, kind: kind)
        }
    }

    /// Closes the field and gives the keys back to the pane in front.
    private func close() {
        sessions.showsOpenPanel = false
        sessions.selectedTab?.focusedPane?.focus()
    }
}

private struct RowView: View {
    let row: OpenConnectionPanel.Row
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .frame(width: 18)
                .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .lineLimit(1)
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .lineLimit(1)
                        .foregroundStyle(isSelected ? AnyShapeStyle(.white.opacity(0.8))
                                                    : AnyShapeStyle(.secondary))
                }
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.clear))
        )
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(accessibilityID)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private var icon: String {
        switch row {
        case let .bookmark(match): match.connection.isFavorite ? "star.fill" : "terminal"
        case .quick: "arrow.right.circle"
        }
    }

    private var title: String {
        switch row {
        case let .bookmark(match): match.connection.name
        case let .quick(address): "Connect to \(address.text)"
        }
    }

    /// The host and the folders, so two bookmarks of the same name in two
    /// folders can be told apart.
    private var detail: String? {
        switch row {
        case let .bookmark(match):
            match.folderPath.isEmpty
                ? match.connection.host
                : "\(match.connection.host) — \(match.folderPath)"
        case .quick:
            "No bookmark. OpenSSH reads ~/.ssh/config for this host."
        }
    }

    private var accessibilityID: String {
        switch row {
        case let .bookmark(match): "open-connection-row-\(match.connection.name)"
        case .quick: "open-connection-row-quick"
        }
    }
}
