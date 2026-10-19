// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

import Foundation

/// Cuts the received bytes into JSON Lines, one line at a time. Fails with an error if the one-line limit is exceeded.
public struct LineFramer: Sendable {
    public enum FramingError: Error, Equatable { case lineTooLong }

    private var buffer = Data()
    private let maxLineBytes: Int

    public init(maxLineBytes: Int = HyperBufProtocol.maxLineBytes) {
        self.maxLineBytes = maxLineBytes
    }

    /// Appends bytes and returns the completed lines (without the newline).
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
