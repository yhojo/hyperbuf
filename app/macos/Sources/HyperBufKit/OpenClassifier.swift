import Foundation
import HyperBufProtocol

/// 検証済みの `open` 要求を、ファイルシステムに照らして分類する(存在・プロジェクトの範囲・信頼するルート)。
public enum OpenClassifier {
    public enum Outcome: Sendable, Equatable {
        /// プロジェクト内。Web コアには、相対パスを渡す。
        case inside(relative: String)
        /// 信頼するルートの内側(承認済み)。絶対パスを渡す。
        case trusted(absolute: String)
        /// 範囲外。利用者の承認が要る。承認されたら `root` を信頼するルートに足す。
        case outside(absolute: String, root: String)
    }

    public static func classify(
        _ open: ValidatedOpen, project: Project, trusted: TrustedRoots
    ) -> Result<Outcome, ProtocolError> {
        // シンボリックリンクは解決したうえで判定する(リンクによる範囲の迂回を防ぐ)
        guard let real = Project.canonicalPath(open.path) else {
            return .failure(ProtocolError(.notFound, "ファイルがありません: \(open.path)"))
        }
        if real.hasPrefix(project.root.path + "/") {
            return .success(.inside(relative: String(real.dropFirst(project.root.path.count + 1))))
        }
        if trusted.contains(real) { return .success(.trusted(absolute: real)) }
        return .success(.outside(absolute: real, root: ProjectLocator.root(for: real)))
    }
}
