// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

import Foundation
import HyperBufProtocol

/// Classifies a validated `open` request against the file system and the judgment (allow / warn paths).
public enum OpenClassifier {
    public enum Outcome: Sendable, Equatable {
        /// Can be opened as is. An absolute path (in `realpath` form).
        case open(absolute: String)
        /// A warn path. The user's approval is needed. If approved, `remember` is remembered (proposed by the app).
        case confirm(absolute: String, remember: String)
    }

    /// - Parameter alwaysConfirmUnlessAllowed: the URL scheme route. Files not under an allow path (including remembered ones)
    ///  are confirmed even outside the warn paths (because this route cannot identify its origin).
    public static func classify(
        _ open: ValidatedOpen, policy: PathPolicy, remembered: RememberedPaths,
        alwaysConfirmUnlessAllowed: Bool = false
    ) -> Result<Outcome, ProtocolError> {
        // Judge after resolving symbolic links (prevents bypass via a link)
        guard let real = PathUtil.canonicalPath(open.path) else {
            return .failure(ProtocolError(.notFound, "No such file: \(open.path)"))
        }
        switch policy.decide(real, remembered: remembered) {
        case .confirm(let remember): return .success(.confirm(absolute: real, remember: remember))
        case .allow:
            if alwaysConfirmUnlessAllowed && !policy.isExplicitlyAllowed(real, remembered: remembered) {
                return .success(.confirm(absolute: real, remember: policy.rememberTarget(for: real)))
            }
            return .success(.open(absolute: real))
        }
    }
}
