import AppKit
import HyperBufKit
import HyperBufProtocol

/// 外部(ソケット・URL スキーム)からの「開く」要求の流れ。docs/integration-protocol.md。
///
///  1. 入力を検証する(`OpenRequestValidator`)。プロジェクトがまだなければ、選ばれるまで保留する
///  2. ファイルシステムに照らして分類する(プロジェクト内 / 信頼するルート / 範囲外 / 存在しない)
///  3. Web コアに渡す(範囲外なら、Web コアのミニバッファで、利用者に確認する)
///  4. Web コアの結果を、要求した相手(ソケットのクライアント)に返す。期限までに返らなければ `timeout`
@MainActor
final class OpenFlow {
    typealias Reply = @Sendable (Response) -> Void

    private struct Pending {
        var reply: Reply?
        /// 範囲外のとき、承認されたら信頼するルートに加えるディレクトリ(アプリが提案したもの)。
        var root: String?
        var timeout: Task<Void, Never>?
    }

    private struct Queued {
        let request: Request
        let reply: Reply?
    }

    private var pending: [String: Pending] = [:]
    private var queued: [Queued] = []
    weak var model: AppModel?

    var hasQueued: Bool { !queued.isEmpty }
    var firstQueuedPath: String? { queued.first?.request.path }

    /// 要求を受け付ける。`reply` が nil なら、結果を返す相手がいない(URL スキーム)。
    func submit(_ request: Request, reply: Reply?) {
        let validated = OpenRequestValidator.validate(
            path: request.path, line: request.line, anchor: request.anchor, version: request.v)
        guard case .success(let open) = validated else {
            if case .failure(let error) = validated { fail(request, reply, error) }
            return
        }
        guard let model, let session = model.session else {
            // プロジェクトがまだ選ばれていない。選ばれるまで保留して、選択を促す
            queued.append(Queued(request: request, reply: reply))
            model?.requestProjectSelection(startingAt: request.project ?? ProjectLocator.root(for: open.path))
            return
        }
        process(request, open, session, reply)
    }

    private func process(_ request: Request, _ open: ValidatedOpen, _ session: ProjectSession, _ reply: Reply?) {
        guard let model else { return }
        let outcome: OpenClassifier.Outcome
        switch OpenClassifier.classify(open, project: session.project, trusted: model.trusted) {
        case .failure(let error): return fail(request, reply, error)
        case .success(let value): outcome = value
        }
        let id = UUID().uuidString
        var instruction: [String: Any] = ["id": id]
        var root: String?
        switch outcome {
        case .inside(let relative): instruction["path"] = relative
        case .trusted(let absolute): instruction["path"] = absolute
        case .outside(let absolute, let proposed):
            instruction["path"] = absolute
            instruction["outside"] = true
            instruction["root"] = proposed
            root = proposed
        }
        if let line = open.line { instruction["line"] = line }
        if let anchor = open.anchor { instruction["anchor"] = anchor }

        var entry = Pending(reply: reply, root: root, timeout: nil)
        let timeoutMs = request.timeoutMs ?? HyperBufProtocol.defaultTimeoutMs
        entry.timeout = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(timeoutMs))
            guard !Task.isCancelled else { return }
            self?.expire(id, request)
        }
        pending[id] = entry
        NSApp.activate(ignoringOtherApps: true)
        session.deliverOpen(instruction)
    }

    private func expire(_ id: String, _ request: Request) {
        guard let entry = pending.removeValue(forKey: id) else { return }
        entry.reply?(.failure(id: request.id, ProtocolError(.timeout, "ユーザーの回答がありませんでした")))
    }

    /// 検証・分類の失敗。ソケットの相手には応答で、URL スキームには、画面(ミニバッファ)で知らせる。
    private func fail(_ request: Request, _ reply: Reply?, _ error: ProtocolError) {
        if let reply {
            reply(.failure(id: request.id, error))
        } else {
            model?.session?.deliverOpen(["id": UUID().uuidString, "path": "", "error": error.message])
        }
    }

    // MARK: Web コアからの結果・確認

    /// Web コアが、要求の結果を返した(`host.respond`)。
    func handleWebResponse(id: String, payload: [String: Any]) {
        guard let entry = pending.removeValue(forKey: id) else { return }
        entry.timeout?.cancel()
        guard let reply = entry.reply else { return }
        if payload["ok"] as? Bool == true {
            reply(.success(id: nil, JSONValue(any: payload["result"] ?? NSNull())))
        } else {
            let error = payload["error"] as? [String: Any]
            reply(
                .failure(
                    id: nil,
                    ProtocolError(
                        rawCode: error?["code"] as? String ?? "internal",
                        message: error?["message"] as? String ?? "失敗しました")))
        }
    }

    /// 範囲外のファイルの確認に、利用者が答えた(`host.confirmOutside`)。
    /// 承認できるのは、アプリが提案したルートだけ。Web 側から、任意のルートは足せない。
    func confirmOutside(id: String, accepted: Bool) -> Bool {
        guard accepted, let model, let root = pending[id]?.root else { return false }
        return model.trusted.add(root)
    }

    // MARK: プロジェクトの選択との連携

    /// プロジェクトが選ばれた(または切り替わった)。保留していた要求を処理する。
    func flushQueued(into session: ProjectSession) {
        let items = queued
        queued.removeAll()
        for item in items {
            if case .success(let open) = OpenRequestValidator.validate(
                path: item.request.path, line: item.request.line, anchor: item.request.anchor,
                version: item.request.v)
            {
                process(item.request, open, session, item.reply)
            }
        }
    }

    /// プロジェクトが選ばれなかった、または切り替わった。待っている要求を、失敗で終える。
    func failAll(_ error: ProtocolError) {
        for item in queued { item.reply?(.failure(id: item.request.id, error)) }
        queued.removeAll()
        for (_, entry) in pending {
            entry.timeout?.cancel()
            entry.reply?(.failure(id: nil, error))
        }
        pending.removeAll()
    }
}
