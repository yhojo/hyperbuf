// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

import Foundation

/// Watching of the files on display (docs/dev/buffer-model.md §8). Watches the file itself and its parent directory
/// with `DispatchSource` (kqueue). It is **non-recursive**, so noise from a repository under build does not reach documents directly under it.
///
///  - Events are batched briefly (about 50ms), the path is `stat`ed again and compared with the previous identity (inode, mtime, size)
///  - If the inode changes through a save method (write a temporary file and replace; rename the original and write a new one), the watch is re-established
///  - If a file disappears, `deleted`. If it is recreated at the same path, `changed`
///  - Notifications arrive on the main queue
public final class FileWatcher: @unchecked Sendable {
    public enum State: Sendable, Equatable {
        case changed
        case deleted
    }

    private struct Signature: Equatable {
        let inode: UInt64
        let mtimeNs: Int64
        let size: Int64
    }

    private final class Entry {
        var file: DispatchSourceFileSystemObject?
        var signature: Signature?
        var pending: DispatchWorkItem?
    }

    private let queue = DispatchQueue(label: "com.yhojo.hyperbuf.filewatcher")
    private var entries: [String: Entry] = [:]
    private var directories: [String: DispatchSourceFileSystemObject] = [:]
    private let onChange: @Sendable (String, State) -> Void
    private let debounce: TimeInterval

    public init(debounce: TimeInterval = 0.05, onChange: @escaping @Sendable (String, State) -> Void) {
        self.debounce = debounce
        self.onChange = onChange
    }

    deinit {
        for entry in entries.values {
            entry.pending?.cancel()
            entry.file?.cancel()
        }
        for source in directories.values { source.cancel() }
    }

    /// Makes these the only files watched (normalized absolute paths).
    public func setPaths(_ paths: Set<String>) {
        queue.sync {
            for path in entries.keys where !paths.contains(path) {
                entries[path]?.pending?.cancel()
                entries[path]?.file?.cancel()
                entries[path] = nil
            }
            for path in paths where entries[path] == nil {
                let entry = Entry()
                entry.signature = Self.signature(path)
                entries[path] = entry
                arm(path, entry)
            }
            // Parent directories: remove the ones no longer needed and add the ones needed
            let wanted = Set(paths.map { ($0 as NSString).deletingLastPathComponent })
            for dir in directories.keys where !wanted.contains(dir) {
                directories[dir]?.cancel()
                directories[dir] = nil
            }
            for dir in wanted where directories[dir] == nil { watchDirectory(dir) }
        }
    }

    // MARK: kqueue

    private func arm(_ path: String, _ entry: Entry) {
        entry.file?.cancel()
        entry.file = nil
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .delete, .rename, .extend, .attrib, .link], queue: queue)
        source.setEventHandler { [weak self] in self?.schedule(path) }
        source.setCancelHandler { close(fd) }
        source.resume()
        entry.file = source
    }

    private func watchDirectory(_ dir: String) {
        let fd = open(dir, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write], queue: queue)
        source.setEventHandler { [weak self] in
            guard let self else { return }
            // The directory contents changed: re-examine the watched files inside it
            for path in self.entries.keys where (path as NSString).deletingLastPathComponent == dir {
                self.schedule(path)
            }
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        directories[dir] = source
    }

    private func schedule(_ path: String) {
        guard let entry = entries[path] else { return }
        entry.pending?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.evaluate(path) }
        entry.pending = work
        queue.asyncAfter(deadline: .now() + debounce, execute: work)
    }

    private func evaluate(_ path: String) {
        guard let entry = entries[path] else { return }
        let now = Self.signature(path)
        guard now != entry.signature else { return }
        let was = entry.signature
        entry.signature = now
        if now == nil {
            entry.file?.cancel()
            entry.file = nil
            if was != nil { notify(path, .deleted) }
            return
        }
        // The inode changed (replaced), or recreated after being deleted: re-attach to the new file
        if was == nil || was?.inode != now?.inode { arm(path, entry) }
        notify(path, .changed)
    }

    private func notify(_ path: String, _ state: State) {
        let callback = onChange
        DispatchQueue.main.async { callback(path, state) }
    }

    private static func signature(_ path: String) -> Signature? {
        var info = stat()
        guard stat(path, &info) == 0 else { return nil }
        let ns = Int64(info.st_mtimespec.tv_sec) * 1_000_000_000 + Int64(info.st_mtimespec.tv_nsec)
        return Signature(inode: UInt64(info.st_ino), mtimeNs: ns, size: Int64(info.st_size))
    }
}
