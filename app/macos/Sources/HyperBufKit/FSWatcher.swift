import CoreServices
import Foundation

/// FSEvents によるファイル監視。ルート配下の Markdown の変更・作成・削除・改名を、相対パスで通知する。
/// 0.5 秒ごとの更新日時の比較(PoC の旧実装)は、削除を検知できず、ファイル数に比例して重いので採用しない。
/// 通知は、メインキューで届く。
public final class FSWatcher: @unchecked Sendable {
    private var stream: FSEventStreamRef?
    private let root: String  // シンボリックリンク解決済みの絶対パス
    private let onChange: @Sendable ([String]) -> Void

    public init(root: URL, latency: TimeInterval = 0.05, onChange: @escaping @Sendable ([String]) -> Void) {
        // FSEvents は、realpath の形で返す(/private/var/...)。比較の基準も、同じ形にそろえる
        self.root = Project.canonicalPath(root.path) ?? root.standardizedFileURL.path
        self.onChange = onChange

        var context = FSEventStreamContext(
            version: 0, info: Unmanaged.passUnretained(self).toOpaque(), retain: nil, release: nil,
            copyDescription: nil)
        let flags = UInt32(
            kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes
                | kFSEventStreamCreateFlagNoDefer)
        let callback: FSEventStreamCallback = { _, info, count, paths, _, _ in
            guard let info else { return }
            let watcher = Unmanaged<FSWatcher>.fromOpaque(info).takeUnretainedValue()
            let list = unsafeBitCast(paths, to: NSArray.self) as? [String] ?? []
            watcher.handle(Array(list.prefix(count)))
        }
        stream = FSEventStreamCreate(
            nil, callback, &context, [self.root] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow), latency, flags)
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
        var relatives: [String] = []
        for path in paths where path.hasSuffix(".md") && path.hasPrefix(root + "/") {
            let relative = String(path.dropFirst(root.count + 1))
            if hasExcludedComponent(relative) { continue }
            if seen.insert(relative).inserted { relatives.append(relative) }
        }
        if !relatives.isEmpty { onChange(relatives) }
    }

    /// 一覧から除く場所(隠しディレクトリ・`node_modules`)の変更は、通知しない。
    private func hasExcludedComponent(_ relative: String) -> Bool {
        relative.split(separator: "/").dropLast().contains {
            $0.hasPrefix(".") || Project.excludedDirectoryNames.contains(String($0))
        }
    }
}
