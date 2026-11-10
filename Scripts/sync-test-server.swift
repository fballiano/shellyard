// A small HTTP server for the folder sync UI test.
//
// It answers every request with one Shellyard connections file, but only
// when the request carries the HTTP Basic credentials inventory / s3cret.
// Any other request gets 401, so a test that sees the entries also proves
// that the credentials arrived.
//
// Usage: swiftc -o server Scripts/sync-test-server.swift && ./server <port>

import Foundation
import Network

let port = NWEndpoint.Port(rawValue: UInt16(CommandLine.arguments[1])!)!
let expected = "Basic " + Data("inventory:s3cret".utf8).base64EncodedString()
let body = Data("""
{ "format": "shellyard.connections", "version": 1, "items": [
  { "type": "connection", "id": "web-1", "name": "synced-web-1", "host": "10.0.0.1" },
  { "type": "folder", "id": "db", "name": "synced-databases", "items": [
    { "type": "connection", "id": "db-1", "name": "synced-db-1", "host": "10.0.1.1" }
  ] }
] }
""".utf8)

func respond(_ connection: NWConnection, status: String, payload: Data) {
    var response = Data(("HTTP/1.1 \(status)\r\nContent-Type: application/json\r\n"
        + "Content-Length: \(payload.count)\r\nConnection: close\r\n\r\n").utf8)
    response.append(payload)
    connection.send(content: response, completion: .contentProcessed { _ in connection.cancel() })
}

let parameters = NWParameters.tcp
parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: port)
let listener = try NWListener(using: parameters)
listener.newConnectionHandler = { connection in
    connection.start(queue: .main)
    connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, _, _ in
        let request = String(decoding: data ?? Data(), as: UTF8.self)
        let authorization = request
            .split(whereSeparator: \.isNewline)
            .first { $0.lowercased().hasPrefix("authorization:") }
            .map { $0.dropFirst("authorization:".count).trimmingCharacters(in: .whitespaces) }
        if authorization == expected {
            respond(connection, status: "200 OK", payload: body)
        } else {
            respond(connection, status: "401 Unauthorized", payload: Data())
        }
    }
}
listener.start(queue: .main)
dispatchMain()
