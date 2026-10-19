// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

import Foundation
import Testing

@testable import HyperBufProtocol

@Suite struct ProtocolTests {
    @Test func requestIgnoresUnknownFieldsAndAcceptsNumericId() throws {
        let json = #"{"v":1,"id":7,"op":"open","path":"/a.md","future":{"x":[1,2]}}"#
        let request = try JSONDecoder().decode(Request.self, from: Data(json.utf8))
        #expect(request.id == "7")
        #expect(request.op == "open")
        #expect(request.path == "/a.md")
    }

    @Test func requestRequiresOp() {
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(Request.self, from: Data(#"{"v":1}"#.utf8))
        }
    }

    @Test func responseEncodesOkAndError() throws {
        let ok = try JSONEncoder().encode(Response.success(id: "1", .object(["path": .string("a.md")])))
        let okObject = try #require(try JSONSerialization.jsonObject(with: ok) as? [String: Any])
        #expect(okObject["ok"] as? Bool == true)
        #expect(okObject["v"] as? Int == 1)
        #expect(okObject["error"] == nil)

        let ng = try JSONEncoder().encode(Response.failure(id: nil, ProtocolError(.outsideProject, "範囲外")))
        let ngObject = try #require(try JSONSerialization.jsonObject(with: ng) as? [String: Any])
        #expect(ngObject["ok"] as? Bool == false)
        #expect((ngObject["error"] as? [String: Any])?["code"] as? String == "outside-project")
        #expect(ngObject["id"] == nil)
    }

    @Test func jsonValueConvertsFromFoundationObjects() throws {
        let object = try JSONSerialization.jsonObject(
            with: Data(#"{"a":true,"b":2,"c":"s","d":[null,false],"e":{}}"#.utf8))
        let value = JSONValue(any: object)
        #expect(
            value
                == .object([
                    "a": .bool(true), "b": .number(2), "c": .string("s"), "d": .array([.null, .bool(false)]),
                    "e": .object([:]),
                ]))
    }

    @Test func framerRejectsTooLongLines() {
        var framer = LineFramer(maxLineBytes: 16)
        #expect(throws: LineFramer.FramingError.lineTooLong) {
            _ = try framer.append(Data(repeating: 97, count: 17))
        }
        var framer2 = LineFramer(maxLineBytes: 16)
        #expect(throws: LineFramer.FramingError.lineTooLong) {
            _ = try framer2.append(Data(repeating: 97, count: 17) + Data([10]))
        }
    }

    @Test func anchorLengthCountsCodePointsNotGraphemes() {
        // A family emoji is one grapheme but five code points. 41 of them make 205, which exceeds 200 and is rejected
        let family = "👨‍👩‍👧"
        #expect(family.count == 1 && family.unicodeScalars.count == 5)
        let longAnchor = String(repeating: family, count: 41)  // 41 graphemes, 205 code points
        guard
            case .failure(let error) = OpenRequestValidator.validate(
                path: "/a.md", line: nil, anchor: longAnchor, version: nil)
        else {
            Issue.record("should be rejected")
            return
        }
        #expect(error.code == ErrorCode.badRequest.rawValue)
    }

    @Test func socketPathFallsBackWhenTooLong() {
        let short = SocketPath.standard(home: "/Users/me", tmp: "/var/folders/xx/T/")
        #expect(short == "/Users/me/Library/Application Support/HyperBuf/hyperbuf.sock")
        let longHome = "/Volumes/" + String(repeating: "x", count: 80)
        let fallback = SocketPath.standard(home: longHome, tmp: "/var/folders/xx/T/")
        #expect(fallback.hasPrefix("/var/folders/xx/T/hyperbuf-"))
        #expect(fallback.utf8.count <= SocketPath.maxBytes)
    }
}
