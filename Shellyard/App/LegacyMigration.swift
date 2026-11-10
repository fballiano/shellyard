//
//  LegacyMigration.swift
//  Shellyard
//

import Foundation

/// Moves the data of Termora, the old name of the app, to Shellyard.
///
/// Until 1.2.0 the app was called Termora, and until 1.4.0 it kept that name
/// in its bundle identifier, its settings keys, and its folders. This runs
/// once, at the first launch, before anything reads a setting. It is the only
/// code that must know the old names. The document reader also accepts the
/// old magic bytes: see `VaultFile.legacyMagic`.
///
/// Nothing is lost when a step fails: the old data stays where it is.
enum LegacyMigration {
    private static let legacyBundleIdentifier = "com.fabrizioballiano.Termora"
    private static let legacyKeyPrefix = "Termora"
    private static let keyPrefix = "Shellyard"
    private static let legacyFolderName = "Termora"
    private static let folderName = "Shellyard"
    private static let doneKey = "ShellyardLegacyMigrationDone"

    static func runOnce() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: doneKey) else { return }
        copySettings(into: defaults)
        moveFolder(in: .applicationSupportDirectory)
        moveFolder(in: .cachesDirectory)
        defaults.set(true, forKey: doneKey)
    }

    /// Copies each `Termora…` setting to the same `Shellyard…` key. A value
    /// that Shellyard already has is kept.
    ///
    /// The paths of the last and the recent documents come across as they
    /// are. A path that ends in `.termora` does not open, and the person
    /// renames the file, as the README tells.
    private static func copySettings(into defaults: UserDefaults) {
        guard let legacy = UserDefaults(suiteName: legacyBundleIdentifier) else { return }
        for (key, value) in legacy.dictionaryRepresentation() where key.hasPrefix(legacyKeyPrefix) {
            let newKey = keyPrefix + key.dropFirst(legacyKeyPrefix.count)
            guard defaults.object(forKey: newKey) == nil else { continue }
            defaults.set(value, forKey: newKey)
        }
    }

    /// Renames `~/Library/<directory>/Termora` to `Shellyard`, when only the
    /// old folder exists.
    private static func moveFolder(in directory: FileManager.SearchPathDirectory) {
        let fileManager = FileManager.default
        guard let base = fileManager.urls(for: directory, in: .userDomainMask).first else { return }
        let old = base.appendingPathComponent(legacyFolderName, isDirectory: true)
        let new = base.appendingPathComponent(folderName, isDirectory: true)
        guard fileManager.fileExists(atPath: old.path),
              !fileManager.fileExists(atPath: new.path) else { return }
        try? fileManager.moveItem(at: old, to: new)
    }
}
