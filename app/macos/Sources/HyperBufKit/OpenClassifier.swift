import Foundation
import HyperBufProtocol

/// 検証済みの `open` 要求を、ファイルシステムと判定(許可 / 警告パス)に照らして分類する。
public enum OpenClassifier {
    public enum Outcome: Sendable, Equatable {
        /// そのまま開ける。絶対パス(`realpath` の形)。
        case open(absolute: String)
        /// 警告パス。利用者の承認が要る。承認されたら `remember` を記憶する(アプリが提案したもの)。
        case confirm(absolute: String, remember: String)
    }

    /// - Parameter alwaysConfirmUnlessAllowed: URL スキーム経由。許可パス(記憶を含む)にないファイルは、
    ///   警告パスの外でも確認する(起点を特定できない経路のため)。
    public static func classify(
        _ open: ValidatedOpen, policy: PathPolicy, remembered: RememberedPaths,
        alwaysConfirmUnlessAllowed: Bool = false
    ) -> Result<Outcome, ProtocolError> {
        // シンボリックリンクは解決したうえで判定する(リンクによる迂回を防ぐ)
        guard let real = PathUtil.canonicalPath(open.path) else {
            return .failure(ProtocolError(.notFound, "ファイルがありません: \(open.path)"))
        }
        switch policy.decide(real, remembered: remembered) {
        case .confirm(let remember): return .success(.confirm(absolute: real, remember: remember))
        case .allow:
            if alwaysConfirmUnlessAllowed && !policy.isExplicitlyAllowed(real, remembered: remembered) {
                return .success(.confirm(absolute: real, remember: policy.rememberTarget(for: real)))
            }
            return .success(.open(absolute: real))
        }
    }
}
