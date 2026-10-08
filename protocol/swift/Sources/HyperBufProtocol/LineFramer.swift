import Foundation

/// 受け取ったバイト列を、JSON Lines の 1 行ごとに切り出す。1 行の上限を超えたら、エラーにする。
public struct LineFramer: Sendable {
    public enum FramingError: Error, Equatable { case lineTooLong }

    private var buffer = Data()
    private let maxLineBytes: Int

    public init(maxLineBytes: Int = HyperBufProtocol.maxLineBytes) {
        self.maxLineBytes = maxLineBytes
    }

    /// バイト列を足して、完成した行(改行を除く)を返す。
    public mutating func append(_ data: Data) throws -> [Data] {
        buffer.append(data)
        var lines: [Data] = []
        while let newline = buffer.firstIndex(of: 10) {
            let line = buffer[buffer.startIndex..<newline]
            if line.count > maxLineBytes { throw FramingError.lineTooLong }
            if !line.isEmpty { lines.append(Data(line)) }
            buffer.removeSubrange(buffer.startIndex...newline)
        }
        if buffer.count > maxLineBytes { throw FramingError.lineTooLong }
        return lines
    }
}
