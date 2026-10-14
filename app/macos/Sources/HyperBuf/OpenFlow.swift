// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

import AppKit
import HyperBufKit
import HyperBufProtocol

/// 外部(ソケット・URL スキーム)からの「開く」要求の流れ。docs/integration-protocol.md、docs/project-model.md §5.2。
///
///  1. 入力を検証する(`OpenRequestValidator`)
///  2. ファイルシステムと判定(許可 / 警告パス)に照らして分類する。URL スキーム経由は、起点を特定できないので、
///     許可パスにないファイルは、警告パスの外でも確認する
///  3. 行き先のフレーム(最後にアクティブだったもの)の Web コアに渡す(警告なら、ミニバッファで利用者に確認する)
///  4. Web コアの結果を、要求した相手(ソケットのクライアント)に返す。期限までに返らなければ `timeout`
@MainActor
final class OpenFlow {
    typealias Reply = @Sendable (Response) -> Void

    private struct Pending {
        var reply: Reply?
        /// 警告のとき、承認されたら記憶するパス(アプリが提案したもの)。
        var remember: String?
        var frame: FrameSession
        var timeout: Task<Void, Never>?
    }

    private struct Queued {
        let request: Request
        let reply: Reply?
        let viaURL: Bool
    }

    private var pending: [String: Pending] = [:]
    private var queued: [Queued] = []
    weak var model: AppModel?

    /// 要求を受け付ける。`reply` が nil なら、結果を返す相手がいない(URL スキーム)。
    func submit(_ request: Request, reply: Reply?, viaURL: Bool = false) {
        guard let model, let frame = model.activeFrame else {
            // フレームがまだない(起動の途中)。できるまで保留する
            queued.append(Queued(request: request, reply: reply, viaURL: viaURL))
            return
        }
        process(request, reply, viaURL: viaURL, frame: frame, model: model)
    }

    private func process(_ request: Request, _ reply: Reply?, viaURL: Bool, frame: FrameSession, model: AppModel) {
        let validated = OpenRequestValidator.validate(
            path: request.path, line: request.line, anchor: request.anchor, version: request.v)
        guard case .success(let open) = validated else {
            if case .failure(let error) = validated { fail(request, reply, error, frame: frame) }
            return
        }
        let outcome: OpenClassifier.Outcome
        switch OpenClassifier.classify(
            open, policy: model.policy, remembered: model.remembered, alwaysConfirmUnlessAllowed: viaURL)
        {
        case .failure(let error): return fail(request, reply, error, frame: frame)
        case .success(let value): outcome = value
        }
        let id = UUID().uuidString
        var instruction: [String: Any] = ["id": id]
        var remember: String?
        switch outcome {
        case .open(let absolute): instruction["path"] = absolute
        case .confirm(let absolute, let proposed):
            instruction["path"] = absolute
            instruction["confirm"] = true
            instruction["remember"] = proposed
            remember = proposed
        }
        if let line = open.line { instruction["line"] = line }
        if let anchor = open.anchor { instruction["anchor"] = anchor }

        var entry = Pending(reply: reply, remember: remember, frame: frame, timeout: nil)
        let timeoutMs = request.timeoutMs ?? HyperBufProtocol.defaultTimeoutMs
        entry.timeout = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(timeoutMs))
            guard !Task.isCancelled else { return }
            self?.expire(id, request)
        }
        pending[id] = entry
        NSApp.activate(ignoringOtherApps: true)
        frame.window?.makeKeyAndOrderFront(nil)
        frame.deliverOpen(instruction)
    }

    private func expire(_ id: String, _ request: Request) {
        guard let entry = pending.removeValue(forKey: id) else { return }
        entry.reply?(.failure(id: request.id, ProtocolError(.timeout, "No response from the user")))
        // 画面に残っている確認(ミニバッファ)も、閉じる。答えても、もう無効なので
        entry.frame.cancelOpen(id)
    }

    /// 検証・分類の失敗。ソケットの相手には応答で、URL スキームには、画面(ミニバッファ)で知らせる。
    private func fail(_ request: Request, _ reply: Reply?, _ error: ProtocolError, frame: FrameSession) {
        if let reply {
            reply(.failure(id: request.id, error))
        } else {
            frame.deliverOpen(["id": UUID().uuidString, "path": "", "error": error.message])
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
                        message: error?["message"] as? String ?? "Failed")))
        }
    }

    /// 警告パスのファイルの確認に、利用者が答えた(`host.confirmOpen`)。
    /// 記憶できるのは、アプリが提案したパスだけ。Web 側から、任意のパスは足せない。
    func confirmOpen(id: String, accepted: Bool) -> Bool {
        guard accepted, let model, let remember = pending[id]?.remember else { return false }
        return model.remembered.add(remember)
    }

    // MARK: 起動との連携

    /// フレームができた。保留していた要求を処理する。
    func flushQueued() {
        guard let model, let frame = model.activeFrame else { return }
        let items = queued
        queued.removeAll()
        for item in items { process(item.request, item.reply, viaURL: item.viaURL, frame: frame, model: model) }
    }

    /// 終了などで、待っている要求を失敗で終える。
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
