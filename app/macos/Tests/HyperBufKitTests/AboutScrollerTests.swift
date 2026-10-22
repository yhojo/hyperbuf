// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

import Testing

@testable import HyperBufKit

@Suite struct AboutScrollerTests {
    private static func make() -> AboutScroller {
        var s = AboutScroller()
        s.setStops([100, 1000, 2000, 3000])
        return s
    }

    private static func run(_ s: inout AboutScroller, seconds: Double) {
        for _ in 0..<Int(seconds * 60) { s.tick(1.0 / 60) }
    }

    @Test func cruisesAtConstantSpeed() {
        var s = Self.make()
        s.start()
        Self.run(&s, seconds: 10)
        #expect(abs(s.position - 320) < 1)
    }

    @Test func doesNotMoveWhileStopped() {
        var s = Self.make()
        Self.run(&s, seconds: 5)
        #expect(s.position == 0)
        s.start()
        Self.run(&s, seconds: 1)
        s.stop()
        let p = s.position
        Self.run(&s, seconds: 5)
        #expect(s.position == p)
    }

    @Test func brakesAndStopsAtTheEnd() {
        var s = Self.make()
        s.position = 3000 - 320
        s.start()
        var previous = s.speed(remaining: 320)
        var seconds = 0.0
        while s.isRunning && seconds < 60 {
            let before = s.position
            s.tick(1.0 / 60)
            let speed = (s.position - before) * 60
            // Never speeds up while braking (the last sub-point snap aside).
            if s.isRunning { #expect(speed <= previous + 0.01) }
            previous = speed
            seconds += 1.0 / 60
        }
        #expect(s.position == 3000)
        #expect(s.isAtEnd)
        #expect(seconds > 15 && seconds < 25)  // a long, gentle stop
    }

    @Test func chapterJumps() {
        var s = Self.make()
        s.nextChapter()
        Self.run(&s, seconds: 2)
        #expect(s.position == 100)
        s.nextChapter()
        Self.run(&s, seconds: 2)
        #expect(s.position == 1000)
        s.previousChapter()
        Self.run(&s, seconds: 2)
        #expect(s.position == 100)
        s.previousChapter()
        Self.run(&s, seconds: 2)
        #expect(s.position == 0)
    }

    @Test func repeatedJumpsAdvanceOneChapterEach() {
        var s = Self.make()
        s.nextChapter()
        s.nextChapter()
        Self.run(&s, seconds: 3)
        #expect(s.position == 1000)
    }

    @Test func jumpingToTheEndStopsThere() {
        var s = Self.make()
        s.start()
        s.position = 2500
        s.nextChapter()
        Self.run(&s, seconds: 3)
        #expect(s.position == 3000)
        #expect(!s.isRunning)
    }

    @Test func startAtTheEndRestarts() {
        var s = Self.make()
        s.position = 3000
        #expect(s.isAtEnd)
        s.toggle()
        #expect(s.isRunning)
        Self.run(&s, seconds: 3)
        #expect(s.position < 200 && s.position > 0)
    }
}
