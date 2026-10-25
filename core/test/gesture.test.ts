// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

import assert from "node:assert/strict";
import test from "node:test";
import { buttonDirection, markerOf, swipeDirection } from "../src/ui/gesture.ts";

test("swiping onto the back / forward carrier entry asks for that move; the middle entry and foreign states do not", () => {
  assert.equal(swipeDirection({ hyperbufHistory: "back" }), "back");
  assert.equal(swipeDirection({ hyperbufHistory: "forward" }), "forward");
  assert.equal(swipeDirection({ hyperbufHistory: "here" }), null);
  assert.equal(swipeDirection(null), null);
  assert.equal(swipeDirection({ hyperbufHistory: "sideways" }), null);
  assert.equal(swipeDirection("back"), null);
});

test("markerOf reads only the three known markers", () => {
  assert.equal(markerOf({ hyperbufHistory: "here" }), "here");
  assert.equal(markerOf({}), null);
  assert.equal(markerOf(undefined), null);
});

test("mouse buttons 3 and 4 are back and forward", () => {
  assert.equal(buttonDirection(3), "back");
  assert.equal(buttonDirection(4), "forward");
  assert.equal(buttonDirection(0), null);
  assert.equal(buttonDirection(1), null);
});
