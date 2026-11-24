// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

import AppKit
import WebKit

/// Printing a frame's page (`print-buffer`, File > Print…). What ends up on paper is decided by the Web core's
/// print style sheet (the document of the selected window, without the frame's chrome); the shell only runs the
/// system print dialog as a sheet of the frame.
@MainActor
enum Printing {
    /// Runs the print dialog for `webView` on `window`. `title` names the job: the dialog proposes `<title>.pdf` when saving as a PDF. `completion` is called when the sheet has closed (printed or cancelled).
    /// Does nothing (and completes at once) while another sheet, e.g. a print dialog, is already open on the window.
    static func run(
        webView: WKWebView, window: NSWindow, title: String, completion: @escaping @MainActor () -> Void
    ) {
        guard window.attachedSheet == nil else { return completion() }
        let info = NSPrintInfo(dictionary: NSPrintInfo.shared.dictionary() as! [NSPrintInfo.AttributeKey: Any])
        // The defaults (72 / 90 pt) are for plain text; documents carry their own spacing
        info.topMargin = margin
        info.bottomMargin = margin
        info.leftMargin = margin
        info.rightMargin = margin
        info.isHorizontallyCentered = false
        info.isVerticallyCentered = false
        var showsPanel = true
        #if DEBUG
            // Integration tests: write a PDF to the given file without showing the dialog
            if let path = ProcessInfo.processInfo.environment["HYPERBUF_TEST_PRINT_PDF"], !path.isEmpty {
                info.jobDisposition = .save
                info.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = URL(fileURLWithPath: path)
                showsPanel = false
            }
        #endif
        let operation = webView.printOperation(with: info)
        // Without it the job is named after the page (`HyperBuf`), and so is the PDF the dialog saves
        operation.jobTitle = title
        operation.showsPrintPanel = showsPanel
        operation.showsProgressPanel = showsPanel
        // Without a frame the operation's view is empty and WebKit prints blank pages
        operation.view?.frame = webView.bounds
        let delegate = Delegate(completion: completion)
        // WKWebView's operation must run as a sheet: the synchronous `run()` blocks the main thread WebKit draws on
        operation.runModal(
            for: window, delegate: delegate,
            didRun: #selector(Delegate.printOperationDidRun(_:success:contextInfo:)),
            contextInfo: Unmanaged.passRetained(delegate).toOpaque())
    }

    private static let margin: CGFloat = 48

    /// AppKit calls it back on the main thread when the sheet closes.
    @MainActor private final class Delegate: NSObject {
        let completion: @MainActor () -> Void

        init(completion: @escaping @MainActor () -> Void) { self.completion = completion }

        @objc func printOperationDidRun(
            _ operation: NSPrintOperation, success: Bool, contextInfo: UnsafeMutableRawPointer?
        ) {
            // Balances the retain that kept the delegate alive while the sheet was open
            contextInfo.map { Unmanaged<Delegate>.fromOpaque($0).release() }
            completion()
        }
    }
}
