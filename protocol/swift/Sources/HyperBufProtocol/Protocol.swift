import Foundation

/// HyperBuf の連携プロトコル(docs/integration-protocol.md §4・§11)。
public enum HyperBufProtocol {
    /// プロトコルのバージョン。要求の `v` が省略されたときは、これとみなす。
    public static let version = 1
    /// 1 行(1 メッセージ)の上限。
    public static let maxLineBytes = 1 << 20
    /// 範囲外の確認など、ユーザーの回答を待つときの既定の期限(ミリ秒)。
    public static let defaultTimeoutMs = 30_000
    /// `anchor` の長さの上限。
    public static let maxAnchorLength = 200
    /// アプリの URL スキーム。アプリの起動と、外部リンクからの「開く」に使う。
    public static let urlScheme = "hyperbuf"
}

public enum RequestOperation: String, Sendable, CaseIterable {
    case ping
    case open
    /// 利用者が「エディタで編集」で指した位置(照合用の情報つき)を返す。
    case getLocation = "get-location"
    /// いまの表示(どの文書の、どのあたりか)を返す。
    case getView = "get-view"
}

public enum ErrorCode: String, Sendable, CaseIterable {
    case badRequest = "bad-request"
    case unsupportedVersion = "unsupported-version"
    case unknownOp = "unknown-op"
    case notFound = "not-found"
    case notMarkdown = "not-markdown"
    case outsideProject = "outside-project"
    case timeout
    case stale
    case `internal`
}

public struct ProtocolError: Error, Sendable, Equatable, Codable {
    public let code: String
    public let message: String

    public init(_ code: ErrorCode, _ message: String) {
        self.code = code.rawValue
        self.message = message
    }

    /// 別の部品(Web コアなど)から届いたコード。未知のコードは、`internal` にそろえる。
    public init(rawCode: String, message: String) {
        self.code = ErrorCode(rawValue: rawCode) == nil ? ErrorCode.internal.rawValue : rawCode
        self.message = message
    }
}

/// 要求。未知のフィールドは無視する(後方互換)。
public struct Request: Sendable, Equatable, Codable {
    public var v: Int?
    public var id: String?
    public var op: String
    public var path: String?
    public var line: Int?
    public var anchor: String?
    public var project: String?
    public var target: String?
    public var timeoutMs: Int?

    public init(
        v: Int? = HyperBufProtocol.version, id: String? = nil, op: RequestOperation, path: String? = nil,
        line: Int? = nil,
        anchor: String? = nil, project: String? = nil, target: String? = nil, timeoutMs: Int? = nil
    ) {
        self.v = v
        self.id = id
        self.op = op.rawValue
        self.path = path
        self.line = line
        self.anchor = anchor
        self.project = project
        self.target = target
        self.timeoutMs = timeoutMs
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        v = try c.decodeIfPresent(Int.self, forKey: .v)
        // id は、文字列でも数値でもよい(文字列にそろえる)
        if let s = try? c.decodeIfPresent(String.self, forKey: .id) {
            id = s
        } else if let n = try? c.decodeIfPresent(Int.self, forKey: .id) {
            id = String(n)
        } else {
            id = nil
        }
        op = try c.decode(String.self, forKey: .op)
        path = try c.decodeIfPresent(String.self, forKey: .path)
        line = try c.decodeIfPresent(Int.self, forKey: .line)
        anchor = try c.decodeIfPresent(String.self, forKey: .anchor)
        project = try c.decodeIfPresent(String.self, forKey: .project)
        target = try c.decodeIfPresent(String.self, forKey: .target)
        timeoutMs = try c.decodeIfPresent(Int.self, forKey: .timeoutMs)
    }
}

public struct Response: Sendable, Equatable, Codable {
    public var v: Int
    public var id: String?
    public var ok: Bool
    public var result: JSONValue?
    public var error: ProtocolError?

    public static func success(id: String?, _ result: JSONValue = .null) -> Response {
        Response(v: HyperBufProtocol.version, id: id, ok: true, result: result, error: nil)
    }

    public static func failure(id: String?, _ error: ProtocolError) -> Response {
        Response(v: HyperBufProtocol.version, id: id, ok: false, result: nil, error: error)
    }
}
