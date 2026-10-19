// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

import Foundation
import HyperBufProtocol
import Testing

@testable import HyperBufIPC

private func shortSocketPath() -> String {
    NSTemporaryDirectory() + "hbc-\(UUID().uuidString.prefix(8))/s.sock"
}

private func cleanup(_ path: String) {
    try? FileManager.default.removeItem(atPath: (path as NSString).deletingLastPathComponent)
}

@Suite(.serialized) struct SocketClientTests {
    @Test func roundTripWithTheRealServer() throws {
        let path = shortSocketPath()
        defer { cleanup(path) }
        let server = SocketServer(path: path) { request, _, reply in
            reply(.success(id: request.id, .object(["path": .string(request.path ?? "")])))
        }
        try server.start()
        defer { server.stop() }
        let response = try SocketClient.send(
            Request(id: "c1", op: .open, path: "/x/日本語.md", line: 3), to: path, timeout: 5)
        #expect(response.ok)
        #expect(response.id == "c1")
        #expect(response.result == .object(["path": .string("/x/日本語.md")]))
    }

    @Test func reportsNotRunningWhenThereIsNoSocketOrNoListener() throws {
        let path = shortSocketPath()
        defer { cleanup(path) }
        #expect(throws: SocketClient.ClientError.notRunning) {
            try SocketClient.send(Request(op: .ping), to: path, timeout: 1)
        }
        #expect(!SocketClient.isListening(at: path))
        #expect(throws: SocketClient.ClientError.notRunning) {
            try SocketClient.send(Request(op: .ping), to: String(repeating: "x", count: 200), timeout: 1)
        }
    }

    @Test func timesOutWhenTheServerDoesNotReply() throws {
        let path = shortSocketPath()
        defer { cleanup(path) }
        // A server that does not respond (a situation where waiting for confirmation continues)
        let server = SocketServer(path: path) { _, _, _ in }
        try server.start()
        defer { server.stop() }
        let started = Date()
        #expect(throws: SocketClient.ClientError.timeout) {
            try SocketClient.send(Request(op: .ping), to: path, timeout: 0.6)
        }
        #expect(Date().timeIntervalSince(started) < 3)
    }

    @Test func receivesErrorResponsesFromTheServer() throws {
        let path = shortSocketPath()
        defer { cleanup(path) }
        let server = SocketServer(path: path) { request, _, reply in
            reply(.failure(id: request.id, ProtocolError(.outsideProject, "範囲外")))
        }
        try server.start()
        defer { server.stop() }
        let response = try SocketClient.send(Request(id: "e", op: .open, path: "/a.md"), to: path, timeout: 5)
        #expect(!response.ok)
        #expect(response.error?.code == "outside-project")
    }

    @Test func detectsListeningServer() throws {
        let path = shortSocketPath()
        defer { cleanup(path) }
        let server = SocketServer(path: path) { request, _, reply in reply(.success(id: request.id)) }
        try server.start()
        #expect(SocketClient.isListening(at: path))
        server.stop()
        #expect(!SocketClient.isListening(at: path))
    }
}
