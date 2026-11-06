//
//  BookmarkSearch.swift
//  TermoraModel
//

import Foundation

/// Finds bookmarks for the Open Connection field.
///
/// Each word of the query must appear in the name, the host, or the folder
/// path of a bookmark. The search does not guess beyond that: Return opens
/// the first row, and a loose match could open the wrong server.
public enum BookmarkSearch {
    public struct Match: Hashable, Sendable, Identifiable {
        public let connection: Connection
        /// The folders above the bookmark, for example `Prod / Web`. Empty at
        /// the top level.
        public let folderPath: String
        /// Lower is better.
        let score: Int

        public var id: UUID { connection.id }
    }

    /// The bookmarks that match, best first.
    ///
    /// An empty query returns every bookmark: favourites first, then by name.
    public static func matches(
        for query: String, in index: DocumentIndex, limit: Int = 100
    ) -> [Match] {
        let words = fold(query).split(whereSeparator: \.isWhitespace).map(String.init)

        var found: [Match] = []
        for connection in index.document.connections {
            let path = index.folderPath(ofParent: connection.parentID)
            var score = 0
            var matchesEveryWord = true
            for word in words {
                guard let wordScore = points(
                    of: word, name: fold(connection.name),
                    host: fold(connection.host), path: fold(path)
                ) else {
                    matchesEveryWord = false
                    break
                }
                score += wordScore
            }
            if matchesEveryWord {
                found.append(Match(connection: connection, folderPath: path, score: score))
            }
        }

        found.sort { left, right in
            if left.score != right.score { return left.score < right.score }
            if left.connection.isFavorite != right.connection.isFavorite {
                return left.connection.isFavorite
            }
            let order = left.connection.name.localizedStandardCompare(right.connection.name)
            if order != .orderedSame { return order == .orderedAscending }
            return left.folderPath.localizedStandardCompare(right.folderPath) == .orderedAscending
        }
        return Array(found.prefix(limit))
    }

    /// Where one word appears. A hit in the name beats a hit in the host,
    /// and a hit in the host beats a hit in the folder path.
    private static func points(of word: String, name: String, host: String, path: String) -> Int? {
        if name.hasPrefix(word) { return 0 }
        if startsAWord(word, in: name) { return 1 }
        if name.contains(word) { return 2 }
        if host.hasPrefix(word) { return 3 }
        if host.contains(word) { return 4 }
        if path.contains(word) { return 5 }
        return nil
    }

    /// True when the word appears just after a space or a mark, as `01` does
    /// in `web-01`.
    private static func startsAWord(_ word: String, in text: String) -> Bool {
        for range in text.ranges(of: word) where range.lowerBound > text.startIndex {
            let before = text[text.index(before: range.lowerBound)]
            if !before.isLetter, !before.isNumber { return true }
        }
        return false
    }

    /// Case and accents do not count.
    private static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
}
