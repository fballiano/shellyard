//
//  FolderSyncEditor.swift
//  Shellyard
//

import SwiftUI
import ShellyardModel

/// The Sync section of the folder editor.
struct FolderSyncEditor: View {
    @Binding var sync: FolderSync?
    let folderID: UUID
    /// Saves the draft of the editor, so the sync uses what is on screen.
    let commit: () -> Void

    @EnvironmentObject private var syncer: SyncController

    private var isOn: Binding<Bool> {
        Binding(
            get: { sync != nil },
            set: { on in sync = on ? (sync ?? FolderSync()) : nil }
        )
    }

    private func field<Value>(_ keyPath: WritableKeyPath<FolderSync, Value>, _ empty: Value) -> Binding<Value> {
        Binding(
            get: { sync?[keyPath: keyPath] ?? empty },
            set: { newValue in sync?[keyPath: keyPath] = newValue }
        )
    }

    var body: some View {
        InspectorSection("Sync") {
            Toggle("Fill this folder from a web address", isOn: isOn)
                .accessibilityIdentifier("syncToggle")

            if let sync {
                Text("The address returns a Shellyard connections file. Each sync adds, "
                     + "changes, and removes the entries it made. The list can also set "
                     + "the settings of this folder. Entries that you add by hand are never "
                     + "touched, and your changes to a synced entry or to this folder stay. "
                     + "When you turn the sync off, the entries stay as normal entries.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                LabeledRow("Address") {
                    TextField("https://inventory.example.com/shellyard.json",
                              text: field(\.url, ""))
                }
                if !sync.url.isEmpty, let problem = sync.urlProblem {
                    Label(problem, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .padding(.leading, 138)
                }
                LabeledRow("User name") {
                    TextField("For HTTP Basic, if the server asks", text: field(\.username, ""))
                }
                LabeledRow("Password") {
                    SecureField("", text: Binding(
                        get: { sync.password.value },
                        set: { newValue in self.sync?.password = Secret(newValue) }
                    ))
                }
                LabeledRow("Sync") {
                    Picker("", selection: field(\.interval, .daily)) {
                        Text("Only when I ask").tag(FolderSync.Interval.manual)
                        Text("Every hour").tag(FolderSync.Interval.hourly)
                        Text("Every day").tag(FolderSync.Interval.daily)
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                LabeledRow("Trust") {
                    VStack(alignment: .leading, spacing: 2) {
                        Toggle("Trust this server",
                               isOn: field(\.trustsServer, false))
                        Text("Keep the commands before connecting, agent forwarding, and X11 "
                             + "forwarding that the server sends. A command runs a program on "
                             + "this Mac, and forwarding gives the far host a way back to it.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if !sync.excludedIDs.isEmpty {
                    LabeledRow("Removed by you") {
                        HStack {
                            Text("\(sync.excludedIDs.count) entries do not come back.")
                                .foregroundStyle(.secondary)
                            Button("Bring Them Back") { self.sync?.excludedIDs = [] }
                        }
                    }
                }

                HStack(spacing: 10) {
                    Button("Sync Now") {
                        commit()
                        Task { await syncer.syncNow(folderID) }
                    }
                    .disabled(sync.validURL == nil || syncer.isRunning(folderID))
                    if syncer.isRunning(folderID) {
                        ProgressView().controlSize(.small)
                    }
                    statusLine
                }
                .padding(.leading, 138)
            }
        }
    }

    @ViewBuilder
    private var statusLine: some View {
        if let status = syncer.status(of: folderID) {
            Label {
                VStack(alignment: .leading, spacing: 1) {
                    Text(status.message).fixedSize(horizontal: false, vertical: true)
                    Text(status.lastAttempt.formatted(date: .abbreviated, time: .shortened))
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: status.failed ? "exclamationmark.triangle.fill" : "checkmark.circle")
                    .foregroundStyle(status.failed ? .orange : .green)
            }
            .font(.caption)
            .textSelection(.enabled)
        }
    }
}

/// Tells the person that a sync made this entry, and what an edit does.
struct SyncedEntryNote: View {
    let link: SyncLink
    @EnvironmentObject private var store: DocumentStore

    var body: some View {
        let source = store.index.folder(link.sourceID)?.name ?? "a folder"
        Label("This entry comes from the sync of “\(source)”. A field that you change "
              + "keeps your value; the other fields follow the list.",
              systemImage: "arrow.triangle.2.circlepath")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
