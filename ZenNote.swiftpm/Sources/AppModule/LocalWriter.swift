import Foundation
import ZenNoteCore

/// Tiny sidecar writes only. Textbook imports use a separate background queue.
/// The serial queue is also the single owner of the pending-write buffer.
final class LocalWriter {
    private let queue = DispatchQueue(label: "zen-note.autosave", qos: .userInitiated)
    private var disk: DiskStore
    private var accessLease: AnyObject?
    private var pending = PendingWrites()
    private var paused = false
    var onStatus: (@MainActor (String?) -> Void)?

    init(disk: DiskStore, accessLease: AnyObject? = nil) {
        self.disk = disk
        self.accessLease = accessLease
    }

    func enqueue(_ files: [String: Data]) {
        queue.async { [self] in
            pending.stage(files)
            if !paused { drain() }
        }
    }

    func read(_ path: String) throws -> Data? {
        try queue.sync {
            if let data = pending.data(for: path) { return data }
            return try disk.read(path)
        }
    }

    func retry() {
        queue.async { [self] in paused = false; drain() }
    }

    /// Call from the folder-switch background job, after visible surfaces flush.
    /// Never abandon queued drafts to connect a different library.
    func finishPending() throws {
        try queue.sync {
            do {
                try pending.flush { try disk.write($0, data: $1) }
                paused = false
                notify(nil)
            } catch {
                paused = true
                notifyFailure(error)
                throw error
            }
        }
    }

    /// Used only after the caller verifies the selected folder's library ID.
    /// Retains pending bytes when permission was lost and the folder is reselected.
    func reconnect(to store: DiskStore, accessLease: AnyObject) throws {
        try queue.sync {
            disk = store
            self.accessLease = accessLease
            do {
                try pending.flush { try disk.write($0, data: $1) }
                paused = false
                notify(nil)
            } catch {
                paused = true
                notifyFailure(error)
                throw error
            }
        }
    }

    func afterDraining(_ completion: @escaping @MainActor () -> Void) {
        queue.async { DispatchQueue.main.async { completion() } }
    }

    private func drain() {
        do {
            try pending.flush { try disk.write($0, data: $1) }
            notify(nil)
        } catch {
            paused = true
            notifyFailure(error)
        }
    }

    private func notifyFailure(_ error: Error) {
        notify("Autosave failed: \(error.localizedDescription) Unsaved changes are retained in memory. Keep the app open and retry or reconnect the same library folder.")
    }

    private func notify(_ error: String?) {
        DispatchQueue.main.async { [weak self] in self?.onStatus?(error) }
    }
}
