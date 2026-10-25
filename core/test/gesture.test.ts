// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

import assert from "node:assert/strict";
import test from "node:test";
import {
  GESTURE_IDLE_MS,
  SWIPE_THRESHOLD_PX,
  SWIPE_WINDOW_MS,
  SwipeTracker,
  buttonDirection,
  canScrollHorizontally,
} from "../src/ui/gesture.ts";

const free = (): boolean => false;

/** A stream of wheel events 10ms apart. Returns what each event produced. */
function stream(tracker: SwipeTracker, dxs: number[], start = 1000, dy = 0, blocked = free) {
  return dxs.map((dx, i) => tracker.feed(dx, dy, start + i * 10, blocked));
}

test("a rightward swipe (negative deltaX) goes back, a leftward one goes forward", () => {
  const back = stream(new SwipeTracker(), Array(10).fill(-20));
  assert.equal(back.filter((r) => r === "back").length, 1);
  const fwd = stream(new SwipeTracker(), Array(10).fill(20));
  assert.equal(fwd.filter((r) => r === "forward").length, 1);
});

test("below the threshold nothing fires", () => {
  const small = Math.floor(SWIPE_THRESHOLD_PX / 4) - 1;
  assert.deepEqual(stream(new SwipeTracker(), Array(3).fill(-small)), [null, null, null]);
});

test("fires once per gesture: the inertia tail stays locked until events stop", () => {
  const t = new SwipeTracker();
  const first = stream(t, Array(30).fill(-20));
  assert.equal(first.filter(Boolean).length, 1);
  // A new gesture after the idle gap fires again
  const next = stream(t, Array(10).fill(-20), 1000 + 30 * 10 + GESTURE_IDLE_MS + 50);
  assert.equal(next.filter(Boolean).length, 1);
});

test("mostly vertical movement does not navigate", () => {
  const r = stream(new SwipeTracker(), Array(20).fill(-10), 1000, 40);
  assert.ok(r.every((x) => x === null));
});

test("a gesture that starts over horizontally scrollable content is left alone for its whole duration", () => {
  const t = new SwipeTracker();
  let asked = 0;
  const r = stream(t, Array(20).fill(-20), 1000, 0, () => {
    asked++;
    return true;
  });
  assert.ok(r.every((x) => x === null));
  assert.equal(asked, 1); // decided once, at the start
});

test("a swipe that starts while vertical scrolling inertia is still flowing still fires", () => {
  const t = new SwipeTracker();
  // 400ms of vertical momentum (no horizontal part), then a clear swipe within the same stream
  for (let i = 0; i < 40; i++) assert.equal(t.feed(0, 30, 1000 + i * 10, free), null);
  const swipe = Array.from({ length: 12 }, (_, i) => t.feed(-12, 4, 1400 + i * 10, free));
  assert.equal(swipe.filter((r) => r === "back").length, 1);
});

test("a slow swipe (spread over the window) and a slightly diagonal one both fire", () => {
  const slow = Array.from({ length: 20 }, (_, i) => new SwipeTracker().feed(0, 0, i, free));
  assert.ok(slow.every((x) => x === null));
  const t = new SwipeTracker();
  const perEvent = Math.ceil((SWIPE_THRESHOLD_PX * 1.2) / (SWIPE_WINDOW_MS / 25)); // reaches it only near the end of the window
  const r = Array.from({ length: SWIPE_WINDOW_MS / 25 }, (_, i) =>
    t.feed(perEvent, 0, 1000 + i * 25, free),
  );
  assert.equal(r.filter((x) => x === "forward").length, 1);
  const diagonal = stream(new SwipeTracker(), Array(10).fill(-16), 1000, 8);
  assert.equal(diagonal.filter((x) => x === "back").length, 1);
});

test("canScrollHorizontally: only overflow auto/scroll elements with room in that direction count", () => {
  const box = { overflowX: "auto", scrollLeft: 0, scrollWidth: 500, clientWidth: 200 };
  assert.equal(canScrollHorizontally([box], 10), true); // room to the right
  assert.equal(canScrollHorizontally([box], -10), false); // already at the left edge
  assert.equal(canScrollHorizontally([{ ...box, scrollLeft: 300 }], 10), false); // at the right edge
  assert.equal(canScrollHorizontally([{ ...box, scrollLeft: 100 }], -10), true);
  assert.equal(canScrollHorizontally([{ ...box, overflowX: "visible" }], 10), false);
  assert.equal(canScrollHorizontally([{ ...box, scrollWidth: 200 }], 10), false); // nothing to scroll
  assert.equal(canScrollHorizontally([], 10), false);
});

test("mouse buttons 3 and 4 are back and forward", () => {
  assert.equal(buttonDirection(3), "back");
  assert.equal(buttonDirection(4), "forward");
  assert.equal(buttonDirection(0), null);
  assert.equal(buttonDirection(1), null);
});
