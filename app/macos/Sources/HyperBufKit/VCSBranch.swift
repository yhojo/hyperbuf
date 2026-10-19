// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

import Foundation

/// モードラインに出す、Git のブランチ名。外部コマンドは使わず、`HEAD` を直接読む(docs/dev/buffer-model.md §6.9)。
///
/// 読むのは、プロジェクト・ルートの `.git`(ディレクトリ、または worktree・submodule の `gitdir:` ファイル)の
/// `HEAD` の先頭 1 行だけ。リポジトリは信頼しない入力なので、サイズ・形式・長さを制限する。
public enum VCSBranch {
    /// 読む量の上限(バイト)。
    static let maxBytes = 4096
    /// 表示するブランチ名の長さの上限(文字数)。超えたら、末尾を省く。
    static let maxLength = 80
    /// detached HEAD のときに示す、短縮ハッシュの桁数。
    static let shortHashLength = 7

    /// `dir` のブランチ名。Git のルートがない、`HEAD` が読めない・形が違うときは nil。
    /// detached HEAD は、短縮ハッシュ。
    public static func read(from dir: String, home: String, ignore: [String] = []) -> String? {
        guard let root = ProjectRoot.markedRoot(from: dir, home: home, ignore: ignore),
            let gitDir = gitDirectory(root)
        else { return nil }
        guard let head = readSmallFile(gitDir + "/HEAD") else { return nil }
        return parse(head)
    }

    /// `HEAD` の内容(先頭 1 行)から、表示名を求める。
    static func parse(_ text: String) -> String? {
        let line = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        if line.hasPrefix("ref:") {
            var ref = line.dropFirst(4).trimmingCharacters(in: .whitespaces)
            for prefix in ["refs/heads/", "refs/"] where ref.hasPrefix(prefix) {
                ref.removeFirst(prefix.count)
                break
            }
            return sanitize(ref)
        }
        let isHash =
            (line.count == 40 || line.count == 64)
            && line.allSatisfy { $0.isASCII && $0.isHexDigit }
        return isHash ? String(line.prefix(shortHashLength)) : nil
    }

    /// 制御文字を含むものは捨て、長すぎるものは省く。
    private static func sanitize(_ name: String) -> String? {
        guard !name.isEmpty, !name.unicodeScalars.contains(where: { $0.properties.generalCategory == .control })
        else { return nil }
        return name.count > maxLength ? String(name.prefix(maxLength - 1)) + "…" : name
    }

    /// ルートの `.git` が、ディレクトリならそれ、`gitdir: <path>` のファイルなら、その指す先。
    private static func gitDirectory(_ root: String) -> String? {
        let dotGit = root + "/.git"
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: dotGit, isDirectory: &isDirectory) else { return nil }
        if isDirectory.boolValue { return dotGit }
        guard let text = readSmallFile(dotGit),
            let line = text.split(whereSeparator: \.isNewline).first, line.hasPrefix("gitdir:")
        else { return nil }
        let target = line.dropFirst("gitdir:".count).trimmingCharacters(in: .whitespaces)
        guard !target.isEmpty, !target.contains("\0") else { return nil }
        return target.hasPrefix("/") ? target : root + "/" + target
    }

    /// 通常のファイルだけを、先頭 `maxBytes` まで読む(FIFO・デバイスなどで止まらないようにする)。
    private static func readSmallFile(_ path: String) -> String? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
            attributes[.type] as? FileAttributeType == .typeRegular,
            let handle = FileHandle(forReadingAtPath: path)
        else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: maxBytes) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
