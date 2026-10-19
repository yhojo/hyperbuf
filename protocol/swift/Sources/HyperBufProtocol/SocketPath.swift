// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

import Foundation

/// Where the socket lives. `sun_path` must be shorter than 104 bytes.
public enum SocketPath {
    public static let maxBytes = 103

    /// `~/Library/Application Support/HyperBuf/hyperbuf.sock`. If too long, under `$TMPDIR` (a per-user isolated
    /// location).
    public static func standard(home: String = NSHomeDirectory(), tmp: String = NSTemporaryDirectory()) -> String {
        let primary = home + "/Library/Application Support/HyperBuf/hyperbuf.sock"
        if primary.utf8.count <= maxBytes { return primary }
        let dir = (tmp as NSString).standardizingPath
        return dir + "/hyperbuf-\(getuid()).sock"
    }
}
