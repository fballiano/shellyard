//
//  TransferController.swift
//  Shellyard
//

import Darwin
import Foundation
import SwiftUI
import ShellyardModel
import UniformTypeIdentifiers

/// Opens the export and import sheets of the Shellyard connections file.
///
/// The File menu and the sidebar both open these sheets, so the request
/// lives here and not in one view.
@MainActor
final class TransferController: ObservableObject {
    /// What to export. `root` is `nil` for the whole document.
    struct ExportRequest: Identifiable {
        let id = UUID()
        let root: UUID?
    }

    @Published var exportRequest: ExportRequest?
    @Published var isImporting = false

    func export(_ root: UUID?) {
        exportRequest = ExportRequest(root: root)
    }

    func beginImport() {
        isImporting = true
    }
}

/// Reads and writes the file on disk.
enum ConnectionsFileStorage {
    /// Writes the file so that only this user can read it, mode 0600.
    ///
    /// The file is made beside the target with the mode already set, then
    /// renamed over it. No other user can read it at any time, even for a
    /// moment, and a crash leaves the old file or the new one.
    /// `FileManager.replaceItemAt` is not used: it keeps the permissions of
    /// the file it replaces.
    static func write(_ data: Data, to url: URL) throws {
        let temporary = url.deletingLastPathComponent()
            .appendingPathComponent(".shellyard-export-\(UUID().uuidString)")
        let descriptor = Darwin.open(temporary.path, O_WRONLY | O_CREAT | O_EXCL, 0o600)
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        do {
            try handle.write(contentsOf: data)
            try handle.close()
            guard Darwin.rename(temporary.path, url.path) == 0 else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
        } catch {
            unlink(temporary.path)
            throw error
        }
    }

    static func read(from url: URL) throws -> ConnectionsFile {
        try ConnectionsFile.decode(Data(contentsOf: url))
    }
}
