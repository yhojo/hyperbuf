// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

import assert from "node:assert/strict";
import test from "node:test";
import { findAll, firstMatch, isCaseSensitive, step, wordAfter } from "../src/isearch.ts";

test("case-sensitive only when the query contains uppercase", () => {
  assert.equal(isCaseSensitive("foo"), false);
  assert.equal(isCaseSensitive("Foo"), true);
  assert.equal(isCaseSensitive("日本語"), false);
  assert.equal(isCaseSensitive(""), false);
});

test("all matches (non-overlapping)", () => {
  assert.deepEqual(findAll("abcabc", "bc", false), [1, 4]);
  assert.deepEqual(findAll("aaaa", "aa", false), [0, 2]); // non-overlapping
  assert.deepEqual(findAll("Foo foo FOO", "foo", false), [0, 4, 8]);
  assert.deepEqual(findAll("Foo foo FOO", "Foo", true), [0]);
  assert.deepEqual(findAll("日本語の日本", "日本", false), [0, 4]);
  assert.deepEqual(findAll("abc", "", false), []);
  assert.deepEqual(findAll("abc", "x", false), []);
});

test("next / previous match (wraps around at the ends)", () => {
  assert.deepEqual(step(3, null, 1), { index: 0, wrapped: false });
  assert.deepEqual(step(3, null, -1), { index: 2, wrapped: false });
  assert.deepEqual(step(3, 0, 1), { index: 1, wrapped: false });
  assert.deepEqual(step(3, 2, 1), { index: 0, wrapped: true });
  assert.deepEqual(step(3, 0, -1), { index: 2, wrapped: true });
  assert.deepEqual(step(0, null, 1), { index: null, wrapped: false });
  assert.deepEqual(step(1, 0, 1), { index: 0, wrapped: true });
});

test("first match: at or after the reference position (before it when backward); otherwise the opposite end", () => {
  const matches = [10, 20, 30];
  assert.deepEqual(firstMatch(matches, 0, 1), { index: 0, wrapped: false });
  assert.deepEqual(firstMatch(matches, 20, 1), { index: 1, wrapped: false }); // includes a match at the reference position
  assert.deepEqual(firstMatch(matches, 21, 1), { index: 2, wrapped: false });
  assert.deepEqual(firstMatch(matches, 99, 1), { index: 0, wrapped: true });
  assert.deepEqual(firstMatch(matches, 25, -1), { index: 1, wrapped: false });
  assert.deepEqual(firstMatch(matches, 5, -1), { index: 2, wrapped: true });
  assert.deepEqual(firstMatch([], 0, 1), { index: null, wrapped: false });
});

test("wordAfter: the text up to the end of the next word (C-w)", () => {
  const text = "Read like a hacker.\nNo tabs";
  assert.equal(wordAfter(text, 0), "Read");
  assert.equal(wordAfter(text, 4), " like");
  assert.equal(wordAfter(text, 2), "ad", "from the middle of a word: the rest of it");
  assert.equal(wordAfter(text, 12), "hacker");
});

test("wordAfter: does not leave the block", () => {
  const text = "Read like a hacker.\nNo tabs";
  assert.equal(wordAfter(text, 18), ".", "no word left: the rest of the block");
  assert.equal(wordAfter(text, 19), "", "at the end of a block");
  assert.equal(wordAfter(text, 20), "No");
  assert.equal(wordAfter(text, text.length), "");
});

test("wordAfter: Japanese is taken a word at a time", () => {
  const text = "設計の方針を決める。";
  const first = wordAfter(text, 0);
  assert.ok(first.length > 0 && first.length < text.length - 1, first);
  assert.ok(text.startsWith(first));
  const second = wordAfter(text, first.length);
  assert.ok(second.length > 0 && first.length + second.length < text.length, second);
});
