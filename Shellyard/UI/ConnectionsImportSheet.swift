//
//  ConnectionsImportSheet.swift
//  Shellyard
//

import AppKit
import SwiftUI
import ShellyardModel
import UniformTypeIdentifiers

/// Reads a Shellyard connections file, shows where its entries will go, and
/// adds them to the open document.
///
/// Nothing changes in the document until the person clicks Import.
struct ConnectionsImportSheet: View {
    @EnvironmentObject private var store: DocumentStore
    @Environment(\.dismiss) private var dismiss

    @State private var sourceURL: URL?
    @State private var file: ConnectionsFile?
    @State private var readProblem: String?
    @State private var destination: UUID?
    @State private var keepCommands = false
    @State private var finished: ConnectionsImport?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let finished {
                FinishedView(result: finished) { dismiss() }
            } else {
                setup
            }
        }
        .padding(24)
        .frame(width: 580)
        .onAppear { destination = store.insertionParent }
    }

    /// The import as it would run now. The preview reads it; the Import
    /// button makes a new one, because each one has its own identifiers.
    private var plan: ConnectionsImport? {
        file.map {
            ConnectionsImport(
                file: $0,
                under: destination,
                firstPosition: store.nextPosition(in: destination),
                keepCommands: keepCommands
            )
        }
    }

    // MARK: - Before the import

    private var setup: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Import Connections").font(.title2.weight(.semibold))
            Text("Shellyard adds the folders and connections of a Shellyard JSON file "
                 + "to the document you have open. Nothing already in it is removed.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Text(sourceURL?.lastPathComponent ?? "No file chosen")
                    .lineLimit(1).truncationMode(.middle)
                    .foregroundStyle(sourceURL == nil ? .secondary : .primary)
                Spacer()
                Button("Choose…") { chooseFile() }
            }

            if let readProblem {
                Label(readProblem, systemImage: "xmark.octagon.fill")
                    .font(.callout)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }

            if let file, let plan {
                Divider()
                destinationPicker
                preview(file)
                Text(addsText(plan))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                if !plan.commands.isEmpty || !plan.refusedCommands.isEmpty {
                    commandsSection(plan)
                }
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Import") { runImport() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(plan?.isEmpty ?? true)
            }
        }
    }

    private var destinationPicker: some View {
        VStack(alignment: .leading, spacing: 4) {
            Picker("Add to", selection: $destination) {
                Text("Top level").tag(UUID?.none)
                ForEach(folderChoices, id: \.id) { choice in
                    Text(choice.path).tag(Optional(choice.id))
                }
            }
            if destination != nil {
                Text("A setting that the file does not give is taken from this folder.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Every folder, by its full path.
    private var folderChoices: [(id: UUID, path: String)] {
        store.index.document.folders
            .map { (id: $0.id, path: store.index.folderPath(ofParent: $0.id)) }
            .sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    // MARK: - The preview

    private struct PreviewRow: Identifiable {
        let id = UUID()
        let depth: Int
        let icon: String
        let tint: Color
        let name: String
        let detail: String
    }

    private func preview(_ file: ConnectionsFile) -> some View {
        let destinationName = destination.map { store.index.folderPath(ofParent: $0) } ?? "Top level"
        return VStack(alignment: .leading, spacing: 0) {
            Label(destinationName, systemImage: destination == nil ? "tray.full" : "folder")
                .font(.callout.weight(.medium))
                .padding(.bottom, 4)
            ScrollView {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(rows(file.items, depth: 1)) { row in
                        HStack(spacing: 6) {
                            Image(systemName: row.icon)
                                .foregroundStyle(row.tint)
                                .frame(width: 16)
                            Text(row.name).lineLimit(1)
                            Text(row.detail)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        .font(.callout)
                        .padding(.leading, CGFloat(row.depth) * 16)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 220)
        }
        .padding(10)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityIdentifier("importPreview")
    }

    private func rows(_ items: [ConnectionsFile.Item], depth: Int) -> [PreviewRow] {
        guard depth < ShellyardModel.Document.maximumDepth else { return [] }
        return items.flatMap { item -> [PreviewRow] in
            switch item {
            case let .folder(folder, _, children):
                let row = PreviewRow(depth: depth, icon: "folder", tint: .secondary,
                                     name: folder.name, detail: "")
                return [row] + rows(children, depth: depth + 1)
            case let .connection(connection, _):
                let needsSecret = connection.settings.authentication.ownValue?.needsSecret == true
                let address = connection.port.map { "\(connection.host):\($0)" } ?? connection.host
                return [PreviewRow(
                    depth: depth,
                    icon: needsSecret ? "key.fill" : "server.rack",
                    tint: needsSecret ? .orange : .secondary,
                    name: connection.name,
                    detail: needsSecret ? "\(address) — needs a password" : address
                )]
            case let .invalid(name, reason):
                return [PreviewRow(depth: depth, icon: "exclamationmark.triangle.fill", tint: .red,
                                   name: name ?? "Unnamed entry", detail: "left out: \(reason)")]
            }
        }
    }

    private func addsText(_ plan: ConnectionsImport) -> String {
        var parts = ["Adds \(plan.folders.count) folders and \(plan.connections.count) connections."]
        if !plan.missingSecrets.isEmpty {
            parts.append("\(plan.missingSecrets.count) need a password.")
        }
        if !plan.problems.isEmpty {
            parts.append("\(plan.problems.count) entries are left out.")
        }
        return parts.joined(separator: " ")
    }

    // MARK: - Commands that run on this Mac

    private func commandsSection(_ plan: ConnectionsImport) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if !plan.commands.isEmpty {
                Toggle(isOn: $keepCommands) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Keep the commands that run on this Mac")
                        Text("Each command runs on this Mac before its connection opens. "
                             + "Keep them only when you trust the file.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                notes(plan.commands, icon: "terminal", tint: .orange)
            }
            if !plan.refusedCommands.isEmpty {
                notes(plan.refusedCommands, icon: "nosign", tint: .red)
            }
        }
    }

    private func notes(_ notes: [ConnectionsImport.Note], icon: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(notes) { note in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: icon).foregroundStyle(tint).frame(width: 16)
                    Text(note.path).font(.callout.weight(.medium))
                    Text(note.text)
                        .font(.callout.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: - Actions

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.json]
        panel.message = "Choose a Shellyard connections file."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        sourceURL = url
        do {
            file = try ConnectionsFileStorage.read(from: url)
            readProblem = nil
        } catch {
            file = nil
            readProblem = error.localizedDescription
        }
    }

    private func runImport() {
        guard let plan, !plan.isEmpty else { return }
        store.update { document in
            document.folders.append(contentsOf: plan.folders)
            document.connections.append(contentsOf: plan.connections)
        }
        finished = plan
    }
}

/// What the import added, and what the person must still do.
private struct FinishedView: View {
    let result: ConnectionsImport
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Import finished", systemImage: "checkmark.circle.fill")
                .font(.headline)
                .foregroundStyle(.green)

            Text("Shellyard added \(result.folders.count) folders and "
                 + "\(result.connections.count) connections.")
                .font(.callout)

            if !result.missingSecrets.isEmpty || !result.problems.isEmpty
                || !result.refusedCommands.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        section("Type the password in", result.missingSecrets, "key.fill", .orange)
                        section("Commands removed", result.refusedCommands, "nosign", .red)
                        section("Left out", result.problems, "exclamationmark.triangle.fill", .red)
                    }
                }
                .frame(maxHeight: 260)
            }

            HStack {
                Spacer()
                Button("Done") { onClose() }.keyboardShortcut(.defaultAction)
            }
        }
    }

    @ViewBuilder
    private func section(_ title: String, _ notes: [ConnectionsImport.Note],
                         _ icon: String, _ tint: Color) -> some View {
        if !notes.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Label("\(title) (\(notes.count))", systemImage: icon)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(tint)
                ForEach(notes) { note in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(note.path)
                            .font(.callout.weight(.medium))
                            .frame(width: 180, alignment: .trailing)
                        Text(note.text)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }
}
