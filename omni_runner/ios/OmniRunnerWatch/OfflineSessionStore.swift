import Foundation

/// Persistent offline queue for completed workout sessions.
///
/// Stores sessions as individual JSON files in the watch's Documents
/// directory so they survive app termination. Each session is identified
/// by its `sessionId`.
///
/// Usage:
/// 1. `save(session:)` — after workout ends, before attempting transfer
/// 2. `remove(sessionId:)` — after receiving ACK from the phone
/// 3. `loadAll()` — on app launch, to retry un-synced sessions
///
/// Thread-safe: all file operations are performed synchronously on the
/// calling thread; callers should dispatch to a background queue for
/// bulk operations.
final class OfflineSessionStore {

    // MARK: - Singleton

    static let shared = OfflineSessionStore()

    // MARK: - Storage Directory

    private let storeDirectory: URL

    private init() {
        let docs = FileManager.default.urls(
            for: .documentDirectory, in: .userDomainMask
        ).first!

        storeDirectory = docs.appendingPathComponent(
            "pending_sessions", isDirectory: true
        )

        // Create directory if needed
        if !FileManager.default.fileExists(atPath: storeDirectory.path) {
            try? FileManager.default.createDirectory(
                at: storeDirectory,
                withIntermediateDirectories: true
            )
        }
    }

    // MARK: - Save

    /// Persist a session JSON to disk.
    ///
    /// Overwrites any existing file with the same sessionId (idempotent).
    func save(session: [String: Any]) {
        guard let sessionId = session["sessionId"] as? String else {
            print("[OfflineStore] Cannot save session without sessionId")
            return
        }

        do {
            let data = try JSONSerialization.data(
                withJSONObject: session, options: [.sortedKeys]
            )
            let fileURL = fileURL(for: sessionId)
            try data.write(to: fileURL, options: .atomic)
            print(
                "[OfflineStore] Saved session: \(sessionId)"
                    + " (\(data.count) bytes)"
            )
        } catch {
            print("[OfflineStore] Save error for \(sessionId): \(error)")
        }
    }

    // MARK: - Remove

    /// Delete a session from the offline store (called after ACK).
    func remove(sessionId: String) {
        let fileURL = fileURL(for: sessionId)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return
        }

        do {
            try FileManager.default.removeItem(at: fileURL)
            print("[OfflineStore] Removed synced session: \(sessionId)")
        } catch {
            print("[OfflineStore] Remove error for \(sessionId): \(error)")
        }
    }

    // MARK: - Load All

    /// Load all pending (un-synced) sessions from disk.
    ///
    /// Returns an array of session JSON dictionaries, sorted by
    /// file modification date (oldest first — FIFO).
    func loadAll() -> [[String: Any]] {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: storeDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: .skipsHiddenFiles
        ) else {
            return []
        }

        let jsonFiles = files
            .filter { $0.pathExtension == "json" }
            .sorted { a, b in
                let dateA = (try? a.resourceValues(
                    forKeys: [.contentModificationDateKey]
                ).contentModificationDate) ?? Date.distantPast
                let dateB = (try? b.resourceValues(
                    forKeys: [.contentModificationDateKey]
                ).contentModificationDate) ?? Date.distantPast
                return dateA < dateB
            }

        var sessions: [[String: Any]] = []

        for fileURL in jsonFiles {
            do {
                let data = try Data(contentsOf: fileURL)
                if let json = try JSONSerialization.jsonObject(with: data)
                    as? [String: Any]
                {
                    sessions.append(json)
                }
            } catch {
                print(
                    "[OfflineStore] Load error for \(fileURL.lastPathComponent)"
                        + ": \(error)"
                )
            }
        }

        if !sessions.isEmpty {
            print("[OfflineStore] Loaded \(sessions.count) pending session(s)")
        }

        return sessions
    }

    // MARK: - Query

    /// Number of pending sessions on disk.
    var pendingCount: Int {
        let files = try? FileManager.default.contentsOfDirectory(
            at: storeDirectory,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        )
        return files?.filter { $0.pathExtension == "json" }.count ?? 0
    }

    /// Check if a specific session exists in the offline store.
    func contains(sessionId: String) -> Bool {
        FileManager.default.fileExists(atPath: fileURL(for: sessionId).path)
    }

    // MARK: - Private

    private func fileURL(for sessionId: String) -> URL {
        let safeName = sessionId
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "..", with: "_")
        return storeDirectory.appendingPathComponent(
            "session_\(safeName).json"
        )
    }
}
