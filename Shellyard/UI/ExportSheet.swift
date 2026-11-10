//
//  ExportSheet.swift
//  Shellyard
//

import AppKit
import SwiftUI
import ShellyardModel
import UniformTypeIdentifiers

/// Writes the whole document, one folder, or one connection to a JSON file.
struct ExportSheet: View {
    let root: UUID?
    @EnvironmentObject private var store: DocumentStore
    @Environment(\.dismiss) private var dismiss

    @State private var includeSecrets = false
    @State private var problem: String?

    private var node: TreeNode? { root.flatMap { store.index.node($0) } }

    private var title: String {
        switch node {
        case nil: "Export All Connections"
        case let .folder(folder)?: "Export the Folder “\(folder.name)”"
        case let .connection(connection)?: "Export the Connection “\(connection.name)”"
        }
    }

    private var file: ConnectionsFile {
        ConnectionsFile(exporting: root, from: store.index, includeSecrets: includeSecrets)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title).font(.title2.weight(.semibold))

            Text(summary)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if root != nil, node?.parentID != nil {
                Text("The folders above it are not in the file. Shellyard writes the "
                     + "settings it inherits from them into the file, so its "
                     + "connections work the same after the import.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            Toggle(isOn: $includeSecrets) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Include passwords and passphrases")
                    Text("When this is off, the connections keep their method, and the "
                         + "import asks for the missing passwords.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityIdentifier("includeSecrets")

            if includeSecrets {
                Label("The file will contain your passwords as plain text. Keep it "
                      + "private, and delete it after the import.",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let problem {
                Label(problem, systemImage: "xmark.octagon.fill")
                    .font(.callout)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Export…") { export() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(root != nil && node == nil)
            }
        }
        .padding(24)
        .frame(width: 480)
    }

    private var summary: String {
        let counts = file.counts
        let folders = counts.folders == 1 ? "1 folder" : "\(counts.folders) folders"
        let connections = counts.connections == 1 ? "1 connection" : "\(counts.connections) connections"
        return "Shellyard writes \(folders) and \(connections) to a JSON file. "
            + "Only your user account can read the file."
    }

    private func export() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(node?.name ?? "Shellyard Connections").json"
        panel.allowedContentTypes = [.json]
        panel.message = "Where should Shellyard save the connections?"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try ConnectionsFileStorage.write(file.encoded(), to: url)
            dismiss()
        } catch {
            problem = "Shellyard could not write the file. \(error.localizedDescription)"
        }
    }
}
