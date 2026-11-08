//
//  AgentService.swift
//  TermoraSSH
//

import Darwin
import Foundation

/// Answers the `termora` command-line tool.
///
/// The service listens on a Unix socket at a fixed, known place, so the tool
/// can find it without any configuration. The socket file is 0600 inside a
/// 0700 directory, which is the same protection that `ssh-agent` relies on:
/// only processes running as you can reach it.
///
/// The service holds no secret and makes no decision. It hands each request
/// to the responder and writes back what the responder returns. The
/// application starts the service when a document unlocks and stops it when
/// the document locks, so a locked document answers nothing.
public final class AgentService: @unchecked Sendable {
    public typealias Responder = @Sendable (AgentRequest) async -> AgentReply

    public let socketURL: URL

    private let responderLock = NSLock()
    private var storedResponder: Responder?
    private let queue = DispatchQueue(label: "com.fabrizioballiano.Termora.agent")
    private var listenDescriptor: Int32 = -1
    private var source: DispatchSourceRead?
    private var boundFile: FileIdentity?

    private static let maximumRequestBytes = 1024 * 1024

    /// Set this before `start()`. It is held behind a lock, because a request
    /// arrives on the socket queue.
    public var responder: Responder? {
        get { responderLock.withLock { storedResponder } }
        set { responderLock.withLock { storedResponder = newValue } }
    }

    public init(socketPath: String = AgentSocket.defaultPath()) throws {
        socketURL = URL(fileURLWithPath: socketPath)
        guard socketURL.path.utf8.count < MemoryLayout<sockaddr_un>.size - 2 else {
            throw AskpassServiceError.socketPathTooLong(socketURL.path)
        }
    }

    deinit { stop() }

    // MARK: - Lifetime

    public func start() throws {
        try queue.sync {
            guard listenDescriptor < 0 else { return }

            // The directory keeps everyone else out, whatever the socket's
            // own mode ends up being.
            try FileManager.default.createDirectory(
                at: socketURL.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )

            // A second copy of the app (a UI test, a debug build) must not
            // take the socket from the copy in use: that copy keeps
            // listening on a file with no name, and `termora` finds nobody.
            if Self.isAnswering(at: socketURL.path) {
                throw AgentServiceError.alreadyServed(socketURL.path)
            }
            // A socket file left behind by a crash would block the bind.
            unlink(socketURL.path)
            let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
            guard descriptor >= 0 else { throw AskpassServiceError.cannotCreateSocket(errno) }
            // Accepted sockets inherit this. Setting it after the accept can
            // fail when the client has already gone.
            var on: Int32 = 1
            setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))

            var address = sockaddr_un()
            address.sun_family = sa_family_t(AF_UNIX)
            address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
            let pathBytes = Array(socketURL.path.utf8)
            withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: pathBytes) }

            let bound = withUnsafePointer(to: &address) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { generic in
                    bind(descriptor, generic, socklen_t(MemoryLayout<sockaddr_un>.size))
                }
            }
            guard bound == 0 else {
                let code = errno
                close(descriptor)
                throw AskpassServiceError.cannotBind(socketURL.path, code)
            }
            chmod(socketURL.path, 0o600)
            guard listen(descriptor, 8) == 0 else {
                let code = errno
                close(descriptor)
                throw AskpassServiceError.cannotBind(socketURL.path, code)
            }

            listenDescriptor = descriptor
            boundFile = Self.fileIdentity(at: socketURL.path)
            let source = DispatchSource.makeReadSource(fileDescriptor: descriptor, queue: queue)
            source.setEventHandler { [weak self] in self?.acceptOne() }
            source.setCancelHandler { close(descriptor) }
            source.resume()
            self.source = source
        }
    }

    public func stop() {
        queue.sync {
            source?.cancel()
            source = nil
            listenDescriptor = -1
            // Remove the file only when it is still ours. Another copy may
            // have bound the path since, and that copy is the one in use.
            if let boundFile, Self.fileIdentity(at: socketURL.path) == boundFile {
                unlink(socketURL.path)
            }
            boundFile = nil
        }
    }

    /// Device and inode of a file, which tell one socket file from another
    /// at the same path.
    private struct FileIdentity: Equatable {
        let device: dev_t
        let inode: ino_t
    }

    private static func fileIdentity(at path: String) -> FileIdentity? {
        var status = stat()
        guard lstat(path, &status) == 0 else { return nil }
        return FileIdentity(device: status.st_dev, inode: status.st_ino)
    }

    /// True when a process accepts connections at the path.
    private static func isAnswering(at path: String) -> Bool {
        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { return false }
        defer { close(descriptor) }
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: Array(path.utf8)) }
        let connected = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { generic in
                connect(descriptor, generic, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        return connected == 0
    }

    // MARK: - Serving

    private func acceptOne() {
        let client = accept(listenDescriptor, nil, nil)
        guard client >= 0 else { return }
        // A client can go away before the reply (another copy of the app
        // only checks that someone answers). A write then must fail, not
        // send SIGPIPE, which ends the whole application.
        var on: Int32 = 1
        setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))

        // The read timeout guards only the request line. The reply may come
        // much later, because a `run` request waits for the connection and,
        // when OpenSSH must ask, for a person.
        var timeout = timeval(tv_sec: 30, tv_usec: 0)
        setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(client, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        guard let responder else {
            Self.reply(to: client, with: .refused("Shellyard is not ready."))
            close(client)
            return
        }
        Task.detached { [client] in
            defer { close(client) }
            // No line at all: the client left, or only checked that someone
            // answers. There is nobody to reply to.
            guard let line = Self.readLine(from: client) else { return }
            guard let request = try? JSONDecoder().decode(AgentRequest.self, from: line) else {
                Self.reply(to: client, with: .refused("The request was not understood."))
                return
            }
            Self.reply(to: client, with: await responder(request))
        }
    }

    private static func readLine(from descriptor: Int32) -> Data? {
        var received = Data()
        var byte: UInt8 = 0
        while received.count < maximumRequestBytes {
            let count = read(descriptor, &byte, 1)
            if count <= 0 { return received.isEmpty ? nil : received }
            if byte == 0x0A { return received }
            received.append(byte)
        }
        return nil
    }

    private static func reply(to descriptor: Int32, with reply: AgentReply) {
        guard var payload = try? JSONEncoder().encode(reply) else { return }
        payload.append(0x0A)
        payload.withUnsafeBytes { buffer in
            guard let base = buffer.baseAddress else { return }
            var sent = 0
            while sent < buffer.count {
                let written = write(descriptor, base + sent, buffer.count - sent)
                if written <= 0 { return }
                sent += written
            }
        }
    }
}

public enum AgentServiceError: Error, LocalizedError {
    /// Another copy of Termora already answers at this path.
    case alreadyServed(String)

    public var errorDescription: String? {
        switch self {
        case let .alreadyServed(path):
            "Another copy of Shellyard already answers the shellyard tool at \(path)."
        }
    }
}
