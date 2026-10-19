// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

import assert from "node:assert/strict";
import test from "node:test";
import {
  currentIndex,
  EPS,
  nextIndex,
  previousIndex,
  sameLevelBackward,
  sameLevelForward,
  upIndex,
} from "../src/outline.ts";

// Example heading structure:
//   0: # A            (level 1, top 0)
//   1: ## A1          (level 2, top 100)
//   2: ### A1a        (level 3, top 200)
//   3: ## A2          (level 2, top 300)
//   4: # B            (level 1, top 400)
//   5: ## B1          (level 2, top 500)
const levels = [1, 2, 3, 2, 1, 2];
const tops = [0, 100, 200, 300, 400, 500];

test("current section: the last heading at or before the top of the screen", () => {
  assert.equal(currentIndex(tops, 0), 0);
  assert.equal(currentIndex(tops, 150), 1);
  assert.equal(currentIndex(tops, 100 - EPS), 1); // (almost) at the top edge of a heading
  assert.equal(currentIndex(tops, 100 - EPS - 1), 0);
  assert.equal(currentIndex(tops, 9999), 5);
  assert.equal(currentIndex([50], 0), -1); // before the first heading
  assert.equal(currentIndex([], 0), -1);
});

test("next heading: the first heading below the top of the screen", () => {
  assert.equal(nextIndex(tops, 0), 1);
  assert.equal(nextIndex(tops, 150), 2);
  assert.equal(nextIndex(tops, 100), 2); // At the top edge of a heading, next means the one after it
  assert.equal(nextIndex(tops, 500), null);
  assert.equal(nextIndex(tops, -100), 0);
  assert.equal(nextIndex([], 0), null);
});

test("previous heading: the last heading above the top of the screen", () => {
  assert.equal(previousIndex(tops, 150), 1); // In the middle of a section, go to that section's heading
  assert.equal(previousIndex(tops, 100), 0); // At the top edge of a heading, previous means the one before it
  assert.equal(previousIndex(tops, 0), null);
  assert.equal(previousIndex(tops, 9999), 5);
  assert.equal(previousIndex([], 0), null);
});

test("heading of the upper level", () => {
  assert.equal(upIndex(levels, 2), 1); // A1a → A1
  assert.equal(upIndex(levels, 1), 0); // A1 → A
  assert.equal(upIndex(levels, 3), 0); // A2 → A
  assert.equal(upIndex(levels, 5), 4); // B1 → B
  assert.equal(upIndex(levels, 0), null);
  assert.equal(upIndex(levels, 4), null);
  assert.equal(upIndex(levels, -1), null);
});

test("next / previous of the same level (not crossing parents)", () => {
  assert.equal(sameLevelForward(levels, 1), 3); // A1 → A2
  assert.equal(sameLevelForward(levels, 3), null); // A2 → none (next would be the parent's sibling B)
  assert.equal(sameLevelForward(levels, 0), 4); // A → B
  assert.equal(sameLevelForward(levels, 2), null); // A1a: no sibling
  assert.equal(sameLevelBackward(levels, 3), 1); // A2 → A1
  assert.equal(sameLevelBackward(levels, 1), null); // A1 → none
  assert.equal(sameLevelBackward(levels, 4), 0); // B → A
  assert.equal(sameLevelBackward(levels, 5), null); // B1: no previous sibling
});

test("works even when heading levels skip (# → ###)", () => {
  const skip = [1, 3, 3, 1];
  assert.equal(upIndex(skip, 1), 0);
  assert.equal(sameLevelForward(skip, 1), 2);
  assert.equal(sameLevelForward(skip, 2), null);
});
