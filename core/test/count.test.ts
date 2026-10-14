// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

import assert from "node:assert/strict";
import test from "node:test";
import { countText, formatCounts } from "../src/count.ts";

test("英語: 行・単語・文字(空白を除く数も)", () => {
  const c = countText("Hello world\n\nSecond line here");
  assert.deepEqual(c, { lines: 2, words: 5, characters: 28, nonWhitespace: 24 });
});

test("空行や前後の空白は数えない。行の区切りの改行は 1 つ数える", () => {
  const c = countText("\n\n  a b  \n\n\n  c  \n");
  assert.equal(c.lines, 2);
  assert.equal(c.characters, 5); // "a b" + "\n" + "c"
  assert.equal(c.nonWhitespace, 3);
});

test("日本語は、辞書による単語分割で数える。文字数は、コードポイントで数える", () => {
  const c = countText("今日は良い天気です。");
  assert.equal(c.lines, 1);
  assert.equal(c.characters, 10);
  assert.equal(c.nonWhitespace, 10);
  assert.ok(c.words >= 3 && c.words <= 8, `words=${c.words}`);
});

test("サロゲートペア(絵文字・𠮷)は、1 文字", () => {
  assert.equal(countText("𠮷野家").characters, 3);
});

test("空のテキスト", () => {
  assert.deepEqual(countText(""), { lines: 0, words: 0, characters: 0, nonWhitespace: 0 });
  assert.deepEqual(countText("\n \n"), { lines: 0, words: 0, characters: 0, nonWhitespace: 0 });
});

test("メッセージは Emacs の体裁で、1 のときは単数形", () => {
  assert.equal(
    formatCounts("Region", { lines: 3, words: 42, characters: 210, nonWhitespace: 180 }),
    "Region has 3 lines, 42 words, 210 characters (180 without whitespace)",
  );
  assert.equal(
    formatCounts("Buffer", { lines: 1, words: 1, characters: 1, nonWhitespace: 1 }),
    "Buffer has 1 line, 1 word, 1 character (1 without whitespace)",
  );
});
