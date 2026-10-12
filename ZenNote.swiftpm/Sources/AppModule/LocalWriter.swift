import Foundation
import ZenNoteCore

/// Tiny sidecar writes only. Textbook imports use a separate background queue.
/// The serial queue is also the single owner of the pending-write buffer.
final class LocalWriter {
    private let queue = DispatchQueue(label: "zen-note.autosave", qos: .userInitiated)
    private let disk: DiskStore
    private var pending = PendingWrites()
    private var paused = false
    var onStatus: (@MainActor (String?) -> Void)?

    init(disk: DiskStore) { self.disk = disk }

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

    func afterDraining(_ completion: @escaping @MainActor () -> Void) {
        queue.async { DispatchQueue.main.async { completion() } }
    }

    private func drain() {
        do {
            try pending.flush { try disk.write($0, data: $1) }
            notify(nil)
        } catch {
            paused = true
            notify("Autosave failed: \(error.localizedDescription) Unsaved changes are retained in memory. Keep the app open and retry.")
        }
    }

    private func notify(_ error: String?) {
        DispatchQueue.main.async { [weak self] in self?.onStatus?(error) }
    }
}
