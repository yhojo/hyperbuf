// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

import Foundation

/// The command that invokes the editor for "Edit in editor" (user setting).
///
/// Rules (permission design for running an external command):
///  - Only a **fixed command the user wrote in the config file**. Document contents, selection and paths go in neither arguments nor environment
///    (the editor fetches the location with `get-location`; there is no room for injection)
///  - Runs as an argument array without a shell. The first is an existing executable absolute path
///  - Standard I/O is not used; it is terminated after the deadline (default 5 seconds)
public struct EditorConfig: Sendable, Equatable {
    /// The command to invoke (the first is an absolute path). If absent, the editor is not invoked and the location is only recorded.
    public var command: [String]?
    /// The editor name shown in the menu ("Edit in <name>").
    public var name: String

    public static let defaultName = "Emacs"

    public static func configURL() -> URL {
        #if DEBUG
            // For tests: only debug builds can swap this, so the user's real config is not used
            if let path = ProcessInfo.processInfo.environment["HYPERBUF_CONFIG"] {
                return URL(fileURLWithPath: path)
            }
        #endif
        return URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Application Support/HyperBuf/config.json")
    }

    /// Reads the config file (JSON). If absent, an empty config. An invalid command is ignored (the editor is not invoked).
    /// Example: `{"editorName": "Emacs", "editorCommand": ["/opt/homebrew/bin/emacsclient", "-n", "-e", "(hyperbuf-edit-here)"]}`
    public static func load(from url: URL = configURL()) -> EditorConfig {
        var config = EditorConfig(command: nil, name: defaultName)
        guard let data = try? Data(contentsOf: url),
            let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { return config }
        if let name = object["editorName"] as? String, !name.isEmpty, name.count <= 40 { config.name = name }
        if let command = object["editorCommand"] as? [String], isValid(command) { config.command = command }
        return config
    }

    /// The first is an existing executable absolute path. Arguments are limited in count and length and contain no NUL.
    public static func isValid(_ command: [String]) -> Bool {
        guard let program = command.first, program.hasPrefix("/"), command.count <= 16 else { return false }
        guard command.allSatisfy({ $0.count <= 1024 && !$0.contains("\0") }) else { return false }
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: program, isDirectory: &isDirectory)
            && !isDirectory.boolValue && FileManager.default.isExecutableFile(atPath: program)
    }

    /// The menu item title.
    public var menuTitle: String {
        command == nil ? "Record Location for Editor" : "Edit in \(name)"
    }
}

public enum EditorCommand {
    public enum Failure: Error, Equatable {
        case notConfigured
        case launchFailed(String)
        case failed(Int32)
        case timedOut
    }

    /// Runs the configured command and waits for it to finish (terminating it after the deadline).
    public static func run(_ config: EditorConfig, timeout: TimeInterval = 5) async -> Result<Void, Failure> {
        guard let command = config.command, EditorConfig.isValid(command) else { return .failure(.notConfigured) }
        return await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: command[0])
            process.arguments = Array(command.dropFirst())
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            let once = Once()
            process.terminationHandler = { finished in
                guard once.take() else { return }
                continuation.resume(
                    returning: finished.terminationStatus == 0
                        ? .success(()) : .failure(.failed(finished.terminationStatus)))
            }
            do {
                try process.run()
            } catch {
                if once.take() { continuation.resume(returning: .failure(.launchFailed("\(error)"))) }
                return
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                guard once.take() else { return }
                process.terminate()
                continuation.resume(returning: .failure(.timedOut))
            }
        }
    }
}

private final class Once: @unchecked Sendable {
    private let lock = NSLock()
    private var taken = false
    func take() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if taken { return false }
        taken = true
        return true
    }
}
