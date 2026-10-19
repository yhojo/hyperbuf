// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

import Foundation

/// Exit codes (docs/dev/integration-protocol.md §6.1).
public enum ExitCode: Int32, Sendable {
    case success = 0
    /// Usage error.
    case usage = 1
    /// File problem (missing, unreadable, not `.md`).
    case file = 2
    /// The app cannot be launched.
    case cannotLaunch = 3
    /// Rejected by the app (out of scope and not approved, expired, etc.).
    case refused = 4
    /// Protocol mismatch, internal error, or an unparseable response.
    case failure = 5
}

public struct UsageError: Error, Equatable {
    public let message: String
    public init(_ message: String) { self.message = message }
}

public struct OpenOptions: Equatable, Sendable {
    /// The files to open, exactly as given in the arguments (`FILE[:LINE]`).
    public var files: [String] = []
    public var line: Int?
    public var anchor: String?
    public var target: String?
    /// Wait a long time for in-app confirmation (out-of-scope paths, etc.).
    public var wait = false
    /// Launch the app without bringing it to the front (only effective when launching).
    public var noActivate = false
    /// Print the built URL instead of opening.
    public var printURL = false
}

public enum Command: Equatable, Sendable {
    case help
    case version
    case open(OpenOptions)
}

public enum Arguments {
    public static let targets: Set<String> = ["current", "split-right", "split-below", "new-frame"]

    public static let usage = """
        Usage: hyperbuf [options] <file>[:<line>] ...

        Open Markdown files in HyperBuf.app. Launches the app if it is not running.

        Options:
          --line <N>         Position by line number (or use <file>:<line>)
          --anchor <ID>      Position by anchor, such as a heading
          --target <T>       Where to show: current (default) | split-right | split-below | new-frame
          --wait             Wait up to 60 seconds for confirmation in the app (e.g. files under a warn path) (default: 3)
          --no-activate      Do not bring the app to the front when launching it
          --print-url        Print the hyperbuf:// URL instead of opening it
          --version          Print the version
          -h, --help         Show this help

        Exit codes: 0 success / 1 usage error / 2 file problem / 3 cannot launch the app /
                    4 rejected or expired / 5 internal error
        """

    public static func parse(_ arguments: [String]) -> Result<Command, UsageError> {
        var options = OpenOptions()
        var index = 0
        func value(for name: String) -> String? {
            index += 1
            return index < arguments.count ? arguments[index] : nil
        }
        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "-h", "--help": return .success(.help)
            case "--version": return .success(.version)
            case "--wait": options.wait = true
            case "--no-activate": options.noActivate = true
            case "--print-url": options.printURL = true
            case "--line":
                guard let text = value(for: argument), let n = Int(text), n > 0 else {
                    return .failure(UsageError("--line requires an integer of 1 or more"))
                }
                options.line = n
            case "--anchor":
                guard let text = value(for: argument), !text.isEmpty else {
                    return .failure(UsageError("--anchor requires a value"))
                }
                options.anchor = text
            case "--target":
                guard let text = value(for: argument), targets.contains(text) else {
                    return .failure(UsageError("--target must be one of: \(targets.sorted().joined(separator: " / "))"))
                }
                options.target = text
            case "--":
                options.files += arguments[(index + 1)...]
                index = arguments.count
            default:
                if argument.hasPrefix("-") && argument != "-" {
                    return .failure(UsageError("Unknown option: \(argument)"))
                }
                options.files.append(argument)
            }
            index += 1
        }
        if options.files.isEmpty { return .failure(UsageError("Specify a file to open")) }
        if options.files.count > 1 && (options.line != nil || options.anchor != nil) {
            return .failure(UsageError("--line and --anchor can be used only with a single file"))
        }
        return .success(.open(options))
    }
}
