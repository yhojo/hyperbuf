import Foundation

/// 終了コード(docs/integration-protocol.md §11.4)。
public enum ExitCode: Int32, Sendable {
    case success = 0
    /// 使い方の誤り。
    case usage = 1
    /// ファイルの問題(ない・読めない・`.md` ではない)。
    case file = 2
    /// アプリを起動できない。
    case cannotLaunch = 3
    /// アプリに拒否された(範囲外で承認されなかった、期限切れなど)。
    case refused = 4
    /// プロトコルの不一致、内部のエラー、応答を解釈できない。
    case failure = 5
}

public struct UsageError: Error, Equatable {
    public let message: String
    public init(_ message: String) { self.message = message }
}

public struct OpenOptions: Equatable, Sendable {
    /// 引数のとおりの、開くファイル(`FILE[:LINE]`)。
    public var files: [String] = []
    public var line: Int?
    public var anchor: String?
    public var project: String?
    public var target: String?
    /// アプリ内の確認(範囲外など)を、長く待つ。
    public var wait = false
    /// アプリを前面に出さずに起動する(起動するときだけ有効)。
    public var noActivate = false
    /// 開かずに、組み立てた URL を出力する。
    public var printURL = false
}

public enum Command: Equatable, Sendable {
    case help
    case version
    case open(OpenOptions)
}

public enum Arguments {
    public static let targets: Set<String> = ["current", "split-right", "split-below", "new-frame"]

    public static let usage = """
        使い方: hyperbuf [オプション] <ファイル>[:<行>] ...

        Markdown を、HyperBuf.app で開く。アプリが起動していなければ、起動する。

        オプション:
          --line <N>         行番号で位置を指定する(<ファイル>:<行> でもよい)
          --anchor <ID>      見出しなどのアンカーで位置を指定する
          --project <DIR>    プロジェクトのルートを明示する(アプリが起動していないとき、最初に開くプロジェクト)
          --target <T>       表示先: current(既定)| split-right | split-below | new-frame
          --wait             アプリ内の確認(プロジェクトの外のファイルなど)を、最大 60 秒待つ(既定は 3 秒)
          --no-activate      起動するとき、アプリを前面に出さない
          --print-url        開かずに、hyperbuf:// の URL を出力する
          --version          バージョンを表示する
          -h, --help         この説明を表示する

        終了コード: 0 成功 / 1 使い方の誤り / 2 ファイルの問題 / 3 アプリを起動できない /
                    4 拒否・期限切れ / 5 内部のエラー
        """

    public static func parse(_ arguments: [String]) -> Result<Command, UsageError> {
        var options = OpenOptions()
        var index = 0
        func value(for name: String) -> String? {
            index += 1
            return index < arguments.count ? arguments[index] : nil
        }
        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "-h", "--help": return .success(.help)
            case "--version": return .success(.version)
            case "--wait": options.wait = true
            case "--no-activate": options.noActivate = true
            case "--print-url": options.printURL = true
            case "--line":
                guard let text = value(for: argument), let n = Int(text), n > 0 else {
                    return .failure(UsageError("--line には、1 以上の整数が必要です"))
                }
                options.line = n
            case "--anchor":
                guard let text = value(for: argument), !text.isEmpty else {
                    return .failure(UsageError("--anchor には、値が必要です"))
                }
                options.anchor = text
            case "--project":
                guard let text = value(for: argument), !text.isEmpty else {
                    return .failure(UsageError("--project には、ディレクトリが必要です"))
                }
                options.project = text
            case "--target":
                guard let text = value(for: argument), targets.contains(text) else {
                    return .failure(UsageError("--target は、\(targets.sorted().joined(separator: " / ")) のいずれかです"))
                }
                options.target = text
            case "--":
                options.files += arguments[(index + 1)...]
                index = arguments.count
            default:
                if argument.hasPrefix("-") && argument != "-" {
                    return .failure(UsageError("未知のオプションです: \(argument)"))
                }
                options.files.append(argument)
            }
            index += 1
        }
        if options.files.isEmpty { return .failure(UsageError("開くファイルを指定してください")) }
        if options.files.count > 1 && (options.line != nil || options.anchor != nil) {
            return .failure(UsageError("--line と --anchor は、ファイルが 1 つのときだけ使えます"))
        }
        return .success(.open(options))
    }
}
