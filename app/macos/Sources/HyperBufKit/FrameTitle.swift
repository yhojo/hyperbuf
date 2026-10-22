// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

import Foundation

/// How the frame (window) title is built (setting `frameTitleFormat`). docs/user/configuration.md.
public enum FrameTitleFormat: String, Sendable, CaseIterable {
    /// `README.md — hyperbuf/docs/user`: the file name, then its directory relative to the project root.
    case `default`
    /// A fixed `HyperBuf`.
    case simple
    /// `README.md`: the file name only.
    case filename
}

/// Builds the frame title from the active buffer (docs/dev/buffer-model.md §6.10).
public enum FrameTitle {
    public static let appName = "HyperBuf"
    /// Separator between the file name and the directory.
    public static let separator = " — "
    /// A directory label longer than this many components is cut from the front (`…/` + the last `keptComponents`).
    public static let maxComponents = 4
    public static let keptComponents = 3

    /// The title without the frame's slot suffix.
    ///
    /// - Parameters:
    ///   - path: the absolute path of the active buffer (nil: no buffer or a virtual one → just the app name).
    ///   - root: its project root when a VCS marker was found (nil: not in a project, or not computed yet).
    ///   - home: the user's home directory, shortened to `~` outside a project.
    public static func title(path: String?, root: String?, home: String, format: FrameTitleFormat) -> String {
        guard format != .simple, let path, path.hasPrefix("/") else { return appName }
        let name = (path as NSString).lastPathComponent
        guard !name.isEmpty else { return appName }
        if format == .filename { return name }
        return name + separator + directoryLabel(PathUtil.parent(path), root: root, home: home)
    }

    /// `<root name>/<relative directory>` inside a project, otherwise the directory with `~` for the home.
    static func directoryLabel(_ dir: String, root: String?, home: String) -> String {
        let label: String
        if let root, PathUtil.isInside(dir, root) {
            let rootName = (root as NSString).lastPathComponent
            let relative = dir.count > root.count ? String(dir.dropFirst(root.count)) : ""
            label = rootName + relative
        } else if home != "/", PathUtil.isInside(dir, home) {
            label = "~" + dir.dropFirst(home.count)
        } else {
            label = dir
        }
        return shorten(label)
    }

    private static func shorten(_ label: String) -> String {
        let parts = label.split(separator: "/", omittingEmptySubsequences: true)
        guard parts.count > maxComponents else { return label }
        return "…/" + parts.suffix(keptComponents).joined(separator: "/")
    }
}
