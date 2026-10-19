// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

import assert from "node:assert/strict";
import test from "node:test";
import { countText, formatCounts } from "../src/count.ts";

test("English: lines, words, characters (also without whitespace)", () => {
  const c = countText("Hello world\n\nSecond line here");
  assert.deepEqual(c, { lines: 2, words: 5, characters: 28, nonWhitespace: 24 });
});

test("blank lines and surrounding whitespace are not counted; a line-separating newline counts as one", () => {
  const c = countText("\n\n  a b  \n\n\n  c  \n");
  assert.equal(c.lines, 2);
  assert.equal(c.characters, 5); // "a b" + "\n" + "c"
  assert.equal(c.nonWhitespace, 3);
});

test("Japanese words are counted by dictionary-based segmentation; characters are counted in code points", () => {
  const c = countText("今日は良い天気です。");
  assert.equal(c.lines, 1);
  assert.equal(c.characters, 10);
  assert.equal(c.nonWhitespace, 10);
  assert.ok(c.words >= 3 && c.words <= 8, `words=${c.words}`);
});

test("a surrogate pair (emoji, 𠮷) is one character", () => {
  assert.equal(countText("𠮷野家").characters, 3);
});

test("empty text", () => {
  assert.deepEqual(countText(""), { lines: 0, words: 0, characters: 0, nonWhitespace: 0 });
  assert.deepEqual(countText("\n \n"), { lines: 0, words: 0, characters: 0, nonWhitespace: 0 });
});

test("the message follows Emacs style, singular for 1", () => {
  assert.equal(
    formatCounts("Region", { lines: 3, words: 42, characters: 210, nonWhitespace: 180 }),
    "Region has 3 lines, 42 words, 210 characters (180 without whitespace)",
  );
  assert.equal(
    formatCounts("Buffer", { lines: 1, words: 1, characters: 1, nonWhitespace: 1 }),
    "Buffer has 1 line, 1 word, 1 character (1 without whitespace)",
  );
});
