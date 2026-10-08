import AppKit
import HyperBufKit

/// 開くプロジェクトの選択。コマンドライン引数のディレクトリ、なければ、パネルでユーザーが選ぶ。
@MainActor
enum ProjectPicker {
    /// 起動時の引数(`HyperBuf <ディレクトリ>`)。
    static func fromArguments(_ arguments: [String] = CommandLine.arguments) -> Project? {
        for argument in arguments.dropFirst() where !argument.hasPrefix("-") {
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: argument, isDirectory: &isDirectory), isDirectory.boolValue {
                return Project(root: URL(fileURLWithPath: argument))
            }
        }
        return nil
    }

    /// ユーザーが、読むディレクトリを選ぶ。選んだものだけが、ファイルアクセスの範囲になる。
    static func choose() -> Project? {
        let panel = NSOpenPanel()
        panel.title = "HyperBuf: プロジェクト(Markdown のあるディレクトリ)を選択"
        panel.prompt = "開く"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return Project(root: url)
    }
}
