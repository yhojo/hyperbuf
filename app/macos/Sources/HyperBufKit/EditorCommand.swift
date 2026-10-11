// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

import Foundation

/// 「エディタで編集」で、エディタを呼び出すコマンド(利用者の設定)。
///
/// 守ること(外部コマンドの実行の権限設計):
///  - コマンドは、**利用者が設定ファイルに書いた、固定のもの**だけ。文書の内容・選択・パスを、引数にも環境にも含めない
///    (位置は、`get-location` で、エディタが取りに来る。注入の余地がない)
///  - シェルを介さず、引数の配列で実行する。先頭は、実在する実行可能な絶対パス
///  - 標準入出力は使わず、期限(既定 5 秒)を過ぎたら、終了させる
public struct EditorConfig: Sendable, Equatable {
    /// 呼び出すコマンド(先頭は絶対パス)。なければ、エディタは呼び出さず、位置を記録するだけ。
    public var command: [String]?
    /// メニューに出すエディタの名前(「<名前> で編集」)。
    public var name: String

    public static let defaultName = "Emacs"

    public static func configURL() -> URL {
        #if DEBUG
            // テスト用: 利用者の実際の設定を使わないよう、デバッグビルドだけ、差し替えられる
            if let path = ProcessInfo.processInfo.environment["HYPERBUF_CONFIG"] {
                return URL(fileURLWithPath: path)
            }
        #endif
        return URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Application Support/HyperBuf/config.json")
    }

    /// 設定ファイル(JSON)を読む。なければ、空の設定。不正なコマンドは、無視する(エディタを呼び出さない)。
    /// 例: `{"editorName": "Emacs", "editorCommand": ["/opt/homebrew/bin/emacsclient", "-n", "-e", "(hyperbuf-edit-here)"]}`
    public static func load(from url: URL = configURL()) -> EditorConfig {
        var config = EditorConfig(command: nil, name: defaultName)
        guard let data = try? Data(contentsOf: url),
            let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { return config }
        if let name = object["editorName"] as? String, !name.isEmpty, name.count <= 40 { config.name = name }
        if let command = object["editorCommand"] as? [String], isValid(command) { config.command = command }
        return config
    }

    /// 先頭が、実在する実行可能な絶対パス。引数は、数・長さに上限があり、NUL を含まない。
    public static func isValid(_ command: [String]) -> Bool {
        guard let program = command.first, program.hasPrefix("/"), command.count <= 16 else { return false }
        guard command.allSatisfy({ $0.count <= 1024 && !$0.contains("\0") }) else { return false }
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: program, isDirectory: &isDirectory)
            && !isDirectory.boolValue && FileManager.default.isExecutableFile(atPath: program)
    }

    /// メニューの項目名。
    public var menuTitle: String {
        command == nil ? "エディタ用に位置を記録" : "\(name) で編集"
    }
}

public enum EditorCommand {
    public enum Failure: Error, Equatable {
        case notConfigured
        case launchFailed(String)
        case failed(Int32)
        case timedOut
    }

    /// 設定されたコマンドを実行して、終わるのを待つ(期限を過ぎたら、終了させる)。
    public static func run(_ config: EditorConfig, timeout: TimeInterval = 5) async -> Result<Void, Failure> {
        guard let command = config.command, EditorConfig.isValid(command) else { return .failure(.notConfigured) }
        return await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: command[0])
            process.arguments = Array(command.dropFirst())
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            let once = Once()
            process.terminationHandler = { finished in
                guard once.take() else { return }
                continuation.resume(
                    returning: finished.terminationStatus == 0
                        ? .success(()) : .failure(.failed(finished.terminationStatus)))
            }
            do {
                try process.run()
            } catch {
                if once.take() { continuation.resume(returning: .failure(.launchFailed("\(error)"))) }
                return
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                guard once.take() else { return }
                process.terminate()
                continuation.resume(returning: .failure(.timedOut))
            }
        }
    }
}

private final class Once: @unchecked Sendable {
    private let lock = NSLock()
    private var taken = false
    func take() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if taken { return false }
        taken = true
        return true
    }
}
