//
//  QuickConnectAddress.swift
//  ShellyardModel
//

import Foundation

/// An address typed into the Open Connection field: `[user@]host[:port]`.
///
/// A quick connection has no bookmark. The address is all there is, so the
/// parser accepts only what OpenSSH can take as a destination, and refuses
/// anything that OpenSSH would read as an option.
public struct QuickConnectAddress: Hashable, Sendable {
    /// The user name, or an empty string when the address names none.
    public var username: String
    public var host: String
    /// The port, or `nil` when the address names none. With no port, OpenSSH
    /// takes the one from `~/.ssh/config`, or 22.
    public var port: Int?

    public init(username: String = "", host: String, port: Int? = nil) {
        self.username = username
        self.host = host
        self.port = port
    }

    /// Reads `host`, `user@host`, `host:2222`, `user@host:2222`,
    /// `[::1]:2222`, or a bare IPv6 address. Returns `nil` for anything else.
    public init?(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty,
              !trimmed.unicodeScalars.contains(where: Self.isSpaceOrControl)
        else { return nil }

        // A user name can hold an `@` (`me@example.com@host`), a host name
        // cannot, so the last `@` divides the two. OpenSSH does the same.
        var rest = Substring(trimmed)
        var username = ""
        if let at = trimmed.lastIndex(of: "@") {
            username = String(trimmed[..<at])
            rest = trimmed[trimmed.index(after: at)...]
            guard Self.isUsername(username) else { return nil }
        }

        var host: Substring
        var portText: Substring?
        if rest.hasPrefix("[") {
            // `[::1]` or `[::1]:2222`: the brackets keep the port apart from
            // the colons of the address.
            guard let close = rest.firstIndex(of: "]") else { return nil }
            host = rest[rest.index(after: rest.startIndex)..<close]
            let after = rest[rest.index(after: close)...]
            if !after.isEmpty {
                guard after.hasPrefix(":") else { return nil }
                portText = after.dropFirst()
            }
        } else if rest.count(where: { $0 == ":" }) == 1, let colon = rest.firstIndex(of: ":") {
            host = rest[..<colon]
            portText = rest[rest.index(after: colon)...]
        } else {
            // No colon, or a bare IPv6 address with no port.
            host = rest
        }

        guard Self.isHost(host) else { return nil }
        var port: Int?
        if let portText {
            guard let value = Int(portText), (1...65535).contains(value) else { return nil }
            port = value
        }

        self.init(username: username, host: String(host), port: port)
    }

    /// The address written out again, for the name of a tab.
    public var text: String {
        var result = username.isEmpty ? "" : "\(username)@"
        let isIPv6 = host.contains(":")
        if isIPv6, port != nil {
            result += "[\(host)]"
        } else {
            result += host
        }
        if let port { result += ":\(port)" }
        return result
    }

    // MARK: - Rules

    private static func isSpaceOrControl(_ scalar: Unicode.Scalar) -> Bool {
        scalar.properties.isWhitespace || scalar.properties.generalCategory == .control
    }

    /// A word that starts with `-` would reach OpenSSH as an option.
    private static func isUsername(_ text: String) -> Bool {
        !text.isEmpty && !text.hasPrefix("-")
    }

    /// Letters, digits, and the marks of a host name or an IP address. An
    /// alias from `~/.ssh/config` follows the same rules.
    private static func isHost(_ text: Substring) -> Bool {
        guard !text.isEmpty, !text.hasPrefix("-") else { return false }
        return text.unicodeScalars.allSatisfy { scalar in
            scalar.properties.isAlphabetic
                || ("0"..."9").contains(scalar)
                || ".-_:%".unicodeScalars.contains(scalar)
        }
    }
}
