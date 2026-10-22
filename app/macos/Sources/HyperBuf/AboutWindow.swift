// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

import AppKit
import HyperBufKit
import Observation
import SwiftUI

/// Drives `AboutScroller` from a display-rate timer while the About window is open.
@MainActor @Observable
final class AboutModel {
    private(set) var scroller = AboutScroller()
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var lastTick: CFTimeInterval = 0

    var position: Double { scroller.position }

    func setStops(_ stops: [Double]) { scroller.setStops(stops) }

    func play() {
        timer?.invalidate()
        lastTick = CACurrentMediaTime()
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func pause() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        let now = CACurrentMediaTime()
        // A long gap (the window was hidden, the machine slept) must not make the text jump.
        let dt = min(now - lastTick, 0.1)
        lastTick = now
        scroller.tick(dt)
    }

    func toggle() { scroller.toggle() }
    func start() { scroller.start() }
    func next() { scroller.nextChapter() }
    func previous() { scroller.previousChapter() }

    /// Space starts / stops; C-n, C-f and Down go to the next chapter; C-p, C-b and Up to the previous one.
    func handle(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let key = event.charactersIgnoringModifiers ?? ""
        if flags.isEmpty, key == " " {
            toggle()
            return true
        }
        if flags == .control {
            switch key {
            case "n", "f": next()
            case "p", "b": previous()
            default: return false
            }
            return true
        }
        if flags.isEmpty || flags == .function {
            switch event.keyCode {
            case 125: next()  // Down
            case 126: previous()  // Up
            default: return false
            }
            return true
        }
        return false
    }
}

private struct ChapterTops: PreferenceKey {
    static let defaultValue: [Int: CGFloat] = [:]
    static func reduce(value: inout [Int: CGFloat], nextValue: () -> [Int: CGFloat]) {
        value.merge(nextValue()) { $1 }
    }
}

private struct FinaleCenter: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

private let spaceName = "aboutScrollContent"

struct AboutView: View {
    let model: AboutModel
    let showNotices: () -> Void
    @State private var viewport: CGFloat = 0
    @State private var tops: [Int: CGFloat] = [:]
    @State private var finaleCenter: CGFloat = 0

    private let ink = Color.primary
    private let dim = Color.secondary

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                identity.frame(width: 230)
                scrollingText
            }
            Divider()
            licenseStrip
        }
        .frame(minWidth: 760, minHeight: 520)
        .background(Color(nsColor: .textBackgroundColor))
    }

    // MARK: Icon, name, version

    private var identity: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(nsImage: NSApp.applicationIconImage)
                .resizable().interpolation(.high)
                .frame(width: 128, height: 128)
            Text(verbatim: "hyperbuf")
                .font(.system(size: 26, weight: .semibold, design: .serif))
            Text(verbatim: "Version \(hyperBufVersion)")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(dim)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Scrolling text

    private var scrollingText: some View {
        GeometryReader { geo in
            let h = geo.size.height
            VStack(spacing: 0) {
                ForEach(Array(AboutContent.chapters.enumerated()), id: \.offset) { index, chapter in
                    chapterView(chapter)
                        .padding(.bottom, 70)
                        .background(
                            GeometryReader { g in
                                Color.clear.preference(
                                    key: ChapterTops.self, value: [index: g.frame(in: .named(spaceName)).minY])
                            })
                }
            }
            .frame(width: min(geo.size.width - 80, 480), alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(width: geo.size.width)
            .coordinateSpace(name: spaceName)
            .offset(y: h - model.position)
            .frame(width: geo.size.width, height: h, alignment: .top)
            .mask(fade)
            .clipped()
            .onAppear { viewport = h }
            .onChange(of: h) { _, new in viewport = new }
        }
        .onPreferenceChange(ChapterTops.self) {
            tops = $0
            updateStops()
        }
        .onPreferenceChange(FinaleCenter.self) {
            finaleCenter = $0
            updateStops()
        }
        .onChange(of: viewport) { updateStops() }
    }

    private var fade: some View {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0), .init(color: .black, location: 0.14),
                .init(color: .black, location: 0.86), .init(color: .clear, location: 1),
            ], startPoint: .top, endPoint: .bottom)
    }

    /// Where each chapter sits nicely (its top at 18% of the viewport); the last stop centers the closing lines.
    private func updateStops() {
        guard viewport > 0, tops.count == AboutContent.chapters.count, finaleCenter > 0 else { return }
        var stops = (0..<(AboutContent.chapters.count - 1)).map { Double(viewport * 0.82 + (tops[$0] ?? 0)) }
        stops.append(Double(viewport / 2 + finaleCenter))
        model.setStops(stops)
    }

    @ViewBuilder private func chapterView(_ chapter: AboutChapter) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(Array(chapter.blocks.enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private func blockView(_ block: AboutBlock) -> some View {
        switch block {
        case .tagline(let text):
            Text(markdown(text))
                .font(.system(size: 21, design: .serif)).italic()
                .foregroundStyle(dim)
                .lineSpacing(6)
        case .heading(let text):
            Text(verbatim: text)
                .font(.system(size: 13, weight: .semibold, design: .serif))
                .tracking(1.2)
                .foregroundStyle(Color.accentColor)
                .padding(.top, 14)
        case .lines(let lines):
            Text(markdown(lines.joined(separator: "\n")))
                .font(bodyFont).foregroundStyle(ink).lineSpacing(9)
        case .paragraph(let text):
            Text(markdown(text)).font(bodyFont).foregroundStyle(ink).lineSpacing(9)
        case .quote(let text):
            Text(verbatim: text)
                .font(.system(size: 20, weight: .semibold, design: .serif))
                .foregroundStyle(ink).lineSpacing(7)
                .padding(.top, 6)
        case .finale:
            finale
        }
    }

    private var bodyFont: Font { .system(size: 16, design: .serif) }

    private var finale: some View {
        VStack(alignment: .leading, spacing: 22) {
            Rectangle().fill(dim.opacity(0.4)).frame(width: 48, height: 1)
            VStack(alignment: .leading, spacing: 8) {
                Text(verbatim: "Half a century of hacking.")
                Text(verbatim: "The machines have changed.")
                Text(verbatim: "The fingers remember.")
            }
            .font(.system(size: 16, design: .serif)).italic().foregroundStyle(dim)
            VStack(alignment: .leading, spacing: 12) {
                Text(verbatim: "hyperbuf").font(.system(size: 30, weight: .bold, design: .serif))
                Text(verbatim: "M-x keep-hacking").font(.system(size: 17, design: .monospaced))
                Text(verbatim: "The story continues...").font(.system(size: 16, design: .serif)).italic()
                    .foregroundStyle(dim)
            }
            .padding(.top, 14)
            .background(
                GeometryReader { g in
                    Color.clear.preference(key: FinaleCenter.self, value: g.frame(in: .named(spaceName)).midY)
                })
        }
    }

    private func markdown(_ source: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: source, options: options)) ?? AttributedString(source)
    }

    // MARK: License strip

    private var licenseStrip: some View {
        HStack(spacing: 14) {
            Text(verbatim: "Apache License 2.0  ·  Copyright 2026 Yasuo Hojo")
            Button("Third-Party Licenses", action: showNotices)
                .buttonStyle(.link)
            Spacer()
            Text(verbatim: "SPC start/stop   C-n / C-p chapter")
                .font(.system(size: 11, design: .monospaced))
        }
        .font(.system(size: 11))
        .lineLimit(1)
        .foregroundStyle(dim)
        .padding(.horizontal, 20).padding(.vertical, 10)
    }
}

/// Hosting view that takes the keyboard for the scroll controls.
private final class AboutHostingView<Content: View>: NSHostingView<Content> {
    var onKey: ((NSEvent) -> Bool)?
    override var acceptsFirstResponder: Bool { true }
    override func keyDown(with event: NSEvent) {
        if onKey?(event) != true { super.keyDown(with: event) }
    }
}

@MainActor
final class AboutWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let model = AboutModel()
    private let showNotices: () -> Void

    init(showNotices: @escaping () -> Void) { self.showNotices = showNotices }

    func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            return
        }
        model.pause()
        let view = AboutHostingView(rootView: AboutView(model: model, showNotices: showNotices))
        view.onKey = { [model] in model.handle($0) }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 820, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        window.title = "About hyperbuf"
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.contentView = view
        window.delegate = self
        window.center()
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(view)
        self.window = window
        model.play()
        // Let the first layout pass finish, then begin to scroll.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [model] in model.start() }
    }

    func windowWillClose(_ notification: Notification) {
        model.pause()
        window = nil
    }
}
