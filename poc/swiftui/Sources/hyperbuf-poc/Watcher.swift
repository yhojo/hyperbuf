import CoreServices
import Foundation

// FSEvents によるファイル監視。ルート配下の Markdown の変更・作成・削除・改名を、相対パスで通知する。
// 0.5 秒ごとの更新日時の比較(旧実装)は、ファイル数に比例して負荷が増えるため置き換える。
final class FSWatcher {
    private var stream: FSEventStreamRef?
    private let root: String  // シンボリックリンク解決済みの絶対パス
    private let onChange: ([String]) -> Void

    init(root: URL, latency: TimeInterval = 0.05, onChange: @escaping ([String]) -> Void) {
        self.root = root.resolvingSymlinksInPath().path
        self.onChange = onChange

        var context = FSEventStreamContext(
            version: 0, info: Unmanaged.passUnretained(self).toOpaque(), retain: nil, release: nil, copyDescription: nil)
        let flags = UInt32(
            kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagNoDefer)
        let callback: FSEventStreamCallback = { _, info, count, paths, _, _ in
            let watcher = Unmanaged<FSWatcher>.fromOpaque(info!).takeUnretainedValue()
            let list = unsafeBitCast(paths, to: NSArray.self) as? [String] ?? []
            watcher.handle(Array(list.prefix(count)))
        }
        stream = FSEventStreamCreate(
            nil, callback, &context, [self.root] as CFArray, FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            latency, flags)
        if let stream {
            FSEventStreamSetDispatchQueue(stream, .main)
            FSEventStreamStart(stream)
        }
    }

    deinit {
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
    }

    private func handle(_ paths: [String]) {
        var seen = Set<String>()
        var rels: [String] = []
        for p in paths where p.hasSuffix(".md") && p.hasPrefix(root + "/") {
            let rel = String(p.dropFirst(root.count + 1))
            if seen.insert(rel).inserted { rels.append(rel) }
        }
        if !rels.isEmpty { onChange(rels) }
    }
}
