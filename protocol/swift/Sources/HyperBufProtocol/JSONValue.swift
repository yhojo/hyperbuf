import Foundation

/// 任意の JSON の値。応答の `result` など、形が操作ごとに違うものに使う。
public enum JSONValue: Sendable, Equatable, Codable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() {
            self = .null
        } else if let v = try? c.decode(Bool.self) {
            self = .bool(v)
        } else if let v = try? c.decode(Double.self) {
            self = .number(v)
        } else if let v = try? c.decode(String.self) {
            self = .string(v)
        } else if let v = try? c.decode([JSONValue].self) {
            self = .array(v)
        } else {
            self = .object(try c.decode([String: JSONValue].self))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let v): try c.encode(v)
        case .number(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .object(let v): try c.encode(v)
        }
    }

    /// `JSONSerialization` が返す値(辞書・配列・文字列・数値・真偽・NSNull)から変換する。
    public init(any value: Any) {
        switch value {
        case is NSNull: self = .null
        case let v as Bool where type(of: value) == type(of: NSNumber(value: true)) && isBool(value): self = .bool(v)
        case let v as NSNumber: self = .number(v.doubleValue)
        case let v as String: self = .string(v)
        case let v as [Any]: self = .array(v.map(JSONValue.init(any:)))
        case let v as [String: Any]: self = .object(v.mapValues(JSONValue.init(any:)))
        default: self = .null
        }
    }

    public var string: String? {
        if case .string(let v) = self { return v }
        return nil
    }
}

private func isBool(_ value: Any) -> Bool {
    guard let number = value as? NSNumber else { return false }
    return CFGetTypeID(number) == CFBooleanGetTypeID()
}
