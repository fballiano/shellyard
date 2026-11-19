//
//  TerminalLink.swift
//  Shellyard
//

import AppKit
import Foundation

/// What a ⌘-click on a link in a pane does.
///
/// The program in the pane sets the target of a link, and that program can
/// run on a server you do not trust. So a web or email link opens, and a
/// file only shows in Finder: Shellyard never opens a file, because opening
/// an app or a script runs it. Any other link goes back to Ghostty, which
/// refuses it.
enum TerminalLink: Equatable {
    /// A web page or an email, for the default application.
    case open(URL)
    /// A folder to open in Finder.
    case showFolder(URL)
    /// A file (or a package, such as an app) to select in Finder.
    case revealFile(URL)

    /// The schemes that open in their default application.
    static let openSchemes: Set<String> = ["http", "https", "mailto"]

    /// What to do with a link, or `nil` to leave it to Ghostty.
    ///
    /// - Parameters:
    ///   - link: The link as Ghostty gives it: a URL, or the text it found,
    ///     which can be a path.
    ///   - localDirectory: The folder of a pane that runs on this Mac, for a
    ///     relative path. `nil` for a pane on a server: a path there names a
    ///     file on the server, so it does nothing here.
    static func action(
        for link: String,
        localDirectory: String?,
        fileManager: FileManager = .default
    ) -> TerminalLink? {
        let url = URL(string: link)
        let scheme = url?.scheme?.lowercased()
        if let url, let scheme, openSchemes.contains(scheme) {
            return .open(url)
        }
        guard let localDirectory else { return nil }

        let path: String
        if scheme == "file" {
            guard let filePath = url?.path, !filePath.isEmpty else { return nil }
            path = filePath
        } else {
            // A path that the text matched. "main.swift:12" reads as a URL
            // with the scheme "main.swift", so the scheme is not checked.
            path = link
        }
        guard let found = existingPath(path, in: localDirectory, fileManager: fileManager)
        else { return nil }

        var isDirectory: ObjCBool = false
        fileManager.fileExists(atPath: found.path, isDirectory: &isDirectory)
        if isDirectory.boolValue, !NSWorkspace.shared.isFilePackage(atPath: found.path) {
            return .showFolder(found)
        }
        return .revealFile(found)
    }

    /// The item on this Mac that the path names, or `nil` when it does not
    /// exist.
    ///
    /// Compilers and test tools print `file:12:5` for a line and a column.
    /// When the path does not exist, up to two such numbers are removed from
    /// its end.
    private static func existingPath(
        _ text: String, in directory: String, fileManager: FileManager
    ) -> URL? {
        var candidate = text
        for _ in 0 ... 2 {
            let expanded = (candidate as NSString).expandingTildeInPath
            let url = expanded.hasPrefix("/")
                ? URL(fileURLWithPath: expanded)
                : URL(fileURLWithPath: directory).appendingPathComponent(expanded)
            let standard = url.standardizedFileURL
            if fileManager.fileExists(atPath: standard.path) { return standard }

            guard let colon = candidate.lastIndex(of: ":"),
                  !candidate[candidate.index(after: colon)...].isEmpty,
                  candidate[candidate.index(after: colon)...].allSatisfy(\.isNumber)
            else { return nil }
            candidate = String(candidate[..<colon])
        }
        return nil
    }

    /// Does what the link asks. Returns `false` when nothing happened.
    @MainActor
    func perform() -> Bool {
        switch self {
        case let .open(url):
            return NSWorkspace.shared.open(url)
        case let .showFolder(url):
            return NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: url.path)
        case let .revealFile(url):
            NSWorkspace.shared.activateFileViewerSelecting([url])
            return true
        }
    }
}
