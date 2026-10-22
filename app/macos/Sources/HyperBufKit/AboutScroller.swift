// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

import Foundation

/// The scrolling state of the About screen: a slow constant-speed scroll that brakes smoothly to a stop at the end,
/// with start/stop and jumps between chapters. Pure logic (no UI) so that it can be unit-tested.
///
/// `position` is how far the text has travelled upward, in points: 0 is the state before the first line appears,
/// `end` is where the closing lines rest.
public struct AboutScroller: Equatable, Sendable {
    public var position: Double = 0
    public private(set) var isRunning = false
    /// Constant scrolling speed in points per second.
    public var cruiseSpeed: Double = 32
    /// Distance before `end` at which the scroll starts to brake (constant deceleration, so it takes
    /// `2 * brakingDistance / cruiseSpeed` seconds to stop).
    public var brakingDistance: Double = 320
    /// Positions at which each chapter is nicely placed on screen, ascending. The last one is the end of the scroll.
    public private(set) var stops: [Double] = []

    private struct Seek: Equatable, Sendable {
        var from: Double
        var to: Double
        var duration: Double
        var elapsed: Double = 0
    }
    private var seek: Seek?

    public init() {}

    public var end: Double { stops.last ?? 0 }
    public var isAtEnd: Bool { seek == nil && position >= end - 0.05 && !stops.isEmpty }
    public var isSeeking: Bool { seek != nil }

    public mutating func setStops(_ newStops: [Double]) {
        stops = newStops.sorted()
        if var s = seek {
            s.to = min(s.to, end)
            seek = s
        }
        position = min(position, end)
    }

    public mutating func start() { if !isAtEnd { isRunning = true } else { restart() } }
    public mutating func stop() { isRunning = false }
    public mutating func toggle() { isRunning ? stop() : start() }

    /// Goes back to the beginning and keeps going.
    public mutating func restart() {
        isRunning = true
        beginSeek(to: 0)
    }

    /// Jumps to the next chapter (or the end when none is left).
    public mutating func nextChapter() {
        let from = seek?.to ?? position
        guard let target = stops.first(where: { $0 > from + 1 }) else { return }
        beginSeek(to: target)
    }

    /// Jumps to the previous chapter; just after arriving at one, this goes to the one before it.
    public mutating func previousChapter() {
        let from = seek?.to ?? position
        beginSeek(to: stops.last(where: { $0 < from - 40 }) ?? 0)
    }

    private mutating func beginSeek(to target: Double) {
        let distance = abs(target - position)
        guard distance > 0.01 else { return }
        seek = Seek(from: position, to: target, duration: min(1.6, max(0.6, distance / 900)))
    }

    /// Speed (points per second) while cruising, `remaining` points before the end.
    func speed(remaining: Double) -> Double {
        remaining >= brakingDistance ? cruiseSpeed : cruiseSpeed * (max(remaining, 0) / brakingDistance).squareRoot()
    }

    public mutating func tick(_ dt: Double) {
        guard dt > 0 else { return }
        if var s = seek {
            s.elapsed += dt
            let t = min(s.elapsed / s.duration, 1)
            position = s.from + (s.to - s.from) * (t * t * (3 - 2 * t))
            if t >= 1 {
                seek = nil
                if position >= end - 0.05 { isRunning = false }
            } else {
                seek = s
            }
            return
        }
        guard isRunning else { return }
        let remaining = end - position
        let step = speed(remaining: remaining) * dt
        if remaining <= 0.05 || step >= remaining {
            position = end
            isRunning = false
        } else {
            position += step
        }
    }
}
