// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

import assert from "node:assert/strict";
import test from "node:test";
import { findAll, firstMatch, isCaseSensitive, step } from "../src/isearch.ts";

test("大文字を含むときだけ、大文字小文字を区別する", () => {
  assert.equal(isCaseSensitive("foo"), false);
  assert.equal(isCaseSensitive("Foo"), true);
  assert.equal(isCaseSensitive("日本語"), false);
  assert.equal(isCaseSensitive(""), false);
});

test("すべての一致(重ならない)", () => {
  assert.deepEqual(findAll("abcabc", "bc", false), [1, 4]);
  assert.deepEqual(findAll("aaaa", "aa", false), [0, 2]); // non-overlapping
  assert.deepEqual(findAll("Foo foo FOO", "foo", false), [0, 4, 8]);
  assert.deepEqual(findAll("Foo foo FOO", "Foo", true), [0]);
  assert.deepEqual(findAll("日本語の日本", "日本", false), [0, 4]);
  assert.deepEqual(findAll("abc", "", false), []);
  assert.deepEqual(findAll("abc", "x", false), []);
});

test("次・前の一致(端で、反対の端に戻る)", () => {
  assert.deepEqual(step(3, null, 1), { index: 0, wrapped: false });
  assert.deepEqual(step(3, null, -1), { index: 2, wrapped: false });
  assert.deepEqual(step(3, 0, 1), { index: 1, wrapped: false });
  assert.deepEqual(step(3, 2, 1), { index: 0, wrapped: true });
  assert.deepEqual(step(3, 0, -1), { index: 2, wrapped: true });
  assert.deepEqual(step(0, null, 1), { index: null, wrapped: false });
  assert.deepEqual(step(1, 0, 1), { index: 0, wrapped: true });
});

test("最初の一致: 基準の位置以降(後ろ向きは、以前)。なければ、反対の端", () => {
  const matches = [10, 20, 30];
  assert.deepEqual(firstMatch(matches, 0, 1), { index: 0, wrapped: false });
  assert.deepEqual(firstMatch(matches, 20, 1), { index: 1, wrapped: false }); // includes a match at the reference position
  assert.deepEqual(firstMatch(matches, 21, 1), { index: 2, wrapped: false });
  assert.deepEqual(firstMatch(matches, 99, 1), { index: 0, wrapped: true });
  assert.deepEqual(firstMatch(matches, 25, -1), { index: 1, wrapped: false });
  assert.deepEqual(firstMatch(matches, 5, -1), { index: 2, wrapped: true });
  assert.deepEqual(firstMatch([], 0, 1), { index: null, wrapped: false });
});
