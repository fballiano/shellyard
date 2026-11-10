//
//  SyncController.swift
//  Shellyard
//

import Combine
import Foundation
import ShellyardModel

/// Fetches the list of each synced folder, applies it, and runs the
/// automatic syncs.
///
/// A sync runs only while the document is open, because the address and its
/// password are inside the document. The time and the result of the last
/// sync stay on this Mac, in `UserDefaults`: a status saved into the document
/// at each sync would change a synced document again and again.
@MainActor
final class SyncController: ObservableObject {
    /// The result of the last sync of one folder, on this Mac.
    struct Status: Codable, Equatable {
        var lastAttempt: Date
        var lastSuccess: Date?
        /// The last sync did not apply cleanly: the request failed, or the
        /// list had bad entries. The sidebar marks the folder.
        var failed: Bool
        /// The request itself failed, so the next automatic try comes soon.
        var retrySoon: Bool
        var message: String
    }

    /// The folders whose sync runs now.
    @Published private(set) var running: Set<UUID> = []
    @Published private(set) var statuses: [UUID: Status] = [:]

    private let store: DocumentStore
    private var cancellables: Set<AnyCancellable> = []
    private var timer: Task<Void, Never>?

    private static let statusKey = "ShellyardSyncStatus"
    /// How often the controller looks for a sync that is due.
    private static let checkInterval: Duration = .seconds(15 * 60)
    /// After a failure, the next automatic try waits at least this long.
    private static let retryDelay: TimeInterval = 15 * 60
    nonisolated static let maximumResponseSize = 20 * 1024 * 1024

    init(store: DocumentStore) {
        self.store = store
        if let data = UserDefaults.standard.data(forKey: Self.statusKey),
           let saved = try? JSONDecoder().decode([UUID: Status].self, from: data) {
            statuses = saved
        }
        // A document that opens runs the syncs that came due while it was
        // closed.
        store.$phase
            .removeDuplicates()
            .sink { [weak self] phase in
                guard phase == .unlocked else { return }
                Task { @MainActor in await self?.runDueSyncs() }
            }
            .store(in: &cancellables)
        timer = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.checkInterval)
                await self?.runDueSyncs()
            }
        }
    }

    deinit {
        timer?.cancel()
    }

    func isRunning(_ folderID: UUID) -> Bool { running.contains(folderID) }

    func status(of folderID: UUID) -> Status? { statuses[folderID] }

    // MARK: - Automatic syncs

    /// Syncs every folder whose interval has passed. An open editor waits:
    /// its draft would write old values over the result when it closes.
    func runDueSyncs() async {
        guard store.isUnlocked, store.editingID == nil else { return }
        let now = Date()
        for folder in store.index.document.folders {
            guard let sync = folder.sync, let interval = sync.interval.seconds,
                  sync.validURL != nil else { continue }
            if let status = statuses[folder.id] {
                let wait = status.retrySoon ? min(interval, Self.retryDelay) : interval
                guard now.timeIntervalSince(status.lastAttempt) >= wait else { continue }
            }
            await syncNow(folder.id)
        }
    }

    // MARK: - One sync

    /// Fetches the list of one folder and applies it. The result goes to the
    /// status of the folder; nothing is shown in an alert, because an
    /// automatic sync can run while the person does something else.
    func syncNow(_ folderID: UUID) async {
        guard !running.contains(folderID),
              let documentURL = store.documentURL,
              let folder = store.index.folder(folderID),
              let sync = folder.sync else { return }

        running.insert(folderID)
        defer { running.remove(folderID) }

        let file: ConnectionsFile
        do {
            file = try await Self.fetch(sync)
        } catch {
            record(folderID, failed: true, retrySoon: true, message: error.localizedDescription)
            return
        }

        // The document may have closed, changed, or lost the folder while
        // the request was out.
        guard store.isUnlocked, store.documentURL == documentURL,
              store.index.folder(folderID)?.sync?.url == sync.url else { return }

        var document = store.index.document
        do {
            let report = try document.applySync(file, toFolder: folderID)
            if document != store.index.document {
                store.update { $0 = document }
            }
            record(folderID, failed: !report.problems.isEmpty, retrySoon: false,
                   message: report.summary)
        } catch {
            record(folderID, failed: true, retrySoon: false, message: error.localizedDescription)
        }
    }

    private func record(_ folderID: UUID, failed: Bool, retrySoon: Bool, message: String) {
        let now = Date()
        var status = statuses[folderID]
            ?? Status(lastAttempt: now, failed: failed, retrySoon: retrySoon, message: message)
        status.lastAttempt = now
        status.failed = failed
        status.retrySoon = retrySoon
        status.message = message
        if !failed { status.lastSuccess = now }
        statuses[folderID] = status
        if let data = try? JSONEncoder().encode(statuses) {
            UserDefaults.standard.set(data, forKey: Self.statusKey)
        }
    }

    // MARK: - The request

    enum FetchError: LocalizedError {
        case badAddress(String)
        case http(Int)
        case tooLarge
        case redirected

        var errorDescription: String? {
            switch self {
            case let .badAddress(problem): problem
            case let .http(code):
                code == 401 || code == 403
                    ? "The server refused the user name or the password (HTTP \(code))."
                    : "The server answered with HTTP \(code)."
            case .tooLarge: "The answer is larger than 20 MB."
            case .redirected:
                "The server sent Shellyard to another address. Shellyard does not follow it, "
                    + "so the password cannot reach another server. Use the final address."
            }
        }
    }

    /// Asks the server for the list.
    ///
    /// The session keeps no cookies, no cache, and no credentials between
    /// requests. A redirect is followed only to the same scheme, host, and
    /// port, so the password never reaches another server.
    nonisolated static func fetch(_ sync: FolderSync) async throws -> ConnectionsFile {
        guard let url = sync.validURL else {
            throw FetchError.badAddress(sync.urlProblem ?? "The address is not valid.")
        }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData,
                                 timeoutInterval: 30)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if !sync.username.isEmpty || !sync.password.isEmpty {
            let pair = Data("\(sync.username):\(sync.password.value)".utf8).base64EncodedString()
            request.setValue("Basic \(pair)", forHTTPHeaderField: "Authorization")
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForResource = 60
        configuration.urlCredentialStorage = nil
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        let session = URLSession(configuration: configuration)
        defer { session.finishTasksAndInvalidate() }

        let (bytes, response) = try await session.bytes(for: request, delegate: SameOriginRedirects())
        guard let http = response as? HTTPURLResponse else { throw FetchError.http(0) }
        if (300 ..< 400).contains(http.statusCode) { throw FetchError.redirected }
        guard (200 ..< 300).contains(http.statusCode) else { throw FetchError.http(http.statusCode) }
        // The limit holds during the download, so a server cannot fill the
        // memory of this Mac.
        guard http.expectedContentLength <= Int64(maximumResponseSize) else { throw FetchError.tooLarge }
        var data = Data()
        for try await byte in bytes {
            data.append(byte)
            if data.count > maximumResponseSize { throw FetchError.tooLarge }
        }
        return try ConnectionsFile.decode(data)
    }
}

/// Refuses a redirect to another scheme, host, or port. The refused redirect
/// comes back as a 3xx answer, and `fetch` reports it.
private final class SameOriginRedirects: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest
    ) async -> URLRequest? {
        guard let from = task.originalRequest?.url, let to = request.url,
              from.scheme == to.scheme, from.host == to.host, from.port == to.port else {
            return nil
        }
        return request
    }
}
