// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

import AppKit
import HyperBufKit
import HyperBufProtocol

/// The flow of "open" requests from outside (socket, URL scheme). docs/dev/integration-protocol.md, docs/dev/file-access.md §2.
///
///  1. Validate the input (`OpenRequestValidator`)
///  2. Classify against the file system and the judgment (allow / warn paths). The URL scheme route cannot identify its origin,
///     so files not under an allow path are confirmed even outside the warn paths
///  3. Hand it to the Web core of the destination frame (the last active one); for a warning, the user is asked in the minibuffer
///  4. Return the Web core's result to the requester (the socket client); `timeout` if nothing comes back by the deadline
@MainActor
final class OpenFlow {
    typealias Reply = @Sendable (Response) -> Void

    private struct Pending {
        var reply: Reply?
        /// The path to remember if approved on a warning (proposed by the app).
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

    /// Accepts a request. If `reply` is nil, there is nobody to return the result to (URL scheme).
    func submit(_ request: Request, reply: Reply?, viaURL: Bool = false) {
        guard let model, let frame = model.activeFrame else {
            // No frame yet (still launching). Hold the request until one exists
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
        // Also close any confirmation still on screen (minibuffer); answering it is no longer valid
        entry.frame.cancelOpen(id)
    }

    /// A validation / classification failure. Socket peers are told in the response; URL scheme requests on screen (minibuffer).
    private func fail(_ request: Request, _ reply: Reply?, _ error: ProtocolError, frame: FrameSession) {
        if let reply {
            reply(.failure(id: request.id, error))
        } else {
            frame.deliverOpen(["id": UUID().uuidString, "path": "", "error": error.message])
        }
    }

    // MARK: Results and confirmations from the Web core

    /// The Web core returned the result of a request (`host.respond`).
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

    /// The user answered the confirmation for a warn-path file (`host.confirmOpen`).
    /// Only the path the app proposed can be remembered. The Web side cannot add an arbitrary path.
    func confirmOpen(id: String, accepted: Bool) -> Bool {
        guard accepted, let model, let remember = pending[id]?.remember else { return false }
        return model.remembered.add(remember)
    }

    // MARK: Coordination with launch

    /// A frame now exists. Process the held requests.
    func flushQueued() {
        guard let model, let frame = model.activeFrame else { return }
        let items = queued
        queued.removeAll()
        for item in items { process(item.request, item.reply, viaURL: item.viaURL, frame: frame, model: model) }
    }

    /// Ends the waiting requests as failures (on quit, etc.).
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
