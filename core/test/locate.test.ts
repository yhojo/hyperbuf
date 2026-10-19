// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

import assert from "node:assert/strict";
import test from "node:test";
import {
  CONTEXT_LENGTH,
  EXPECT_LIMIT,
  lineStarts,
  locateInSource,
  offsetToPosition,
  uniqueMatch,
} from "../src/locate.ts";

/** Block positions of paragraphs (UTF-16 offsets). In tests, paragraphs separated by blank lines count as blocks. */
function paragraphs(text: string): { start: number; end: number }[] {
  const out: { start: number; end: number }[] = [];
  let offset = 0;
  for (const chunk of text.split(/\n\n/)) {
    out.push({ start: offset, end: offset + chunk.length });
    offset += chunk.length + 2;
  }
  return out;
}

const locate = (text: string, block: number, selection: string) => {
  const b = paragraphs(text)[block];
  assert.ok(b);
  return locateInSource({
    path: "a.md",
    text,
    version: 1,
    blockStart: b.start,
    blockEnd: b.end,
    selection,
  });
};

test("line start offsets (LF, CRLF, CR)", () => {
  assert.deepEqual(lineStarts("a\nb\nc"), [0, 2, 4]);
  assert.deepEqual(lineStarts("a\r\nb\r\nc"), [0, 3, 6]);
  assert.deepEqual(lineStarts("a\rb"), [0, 2]);
  assert.deepEqual(lineStarts(""), [0]);
});

test("columns are counted in code points (a surrogate pair is one character)", () => {
  const text = "😀a日本\nxyz";
  const starts = lineStarts(text);
  // "😀" is 2 units in UTF-16. The position of "a" is 2 in UTF-16 and 1 in code points
  assert.deepEqual(offsetToPosition(starts, text, 2), { line: 1, column: 2 });
  assert.deepEqual(offsetToPosition(starts, text, 3), { line: 1, column: 3 });
  assert.deepEqual(offsetToPosition(starts, text, text.indexOf("xyz") + 1), { line: 2, column: 2 });
});

test("exact when the selection occurs exactly once in the block", () => {
  const text = "# 見出し\n\nこの文には、独自の語があります。\n\n別の段落です。";
  const loc = locate(text, 1, "独自の語");
  assert.equal(loc.precision, "exact");
  assert.equal(loc.expect, "独自の語");
  // "この文には、" is 6 characters, so "独自の語" starts at column 7 (the end is an exclusive position)
  assert.deepEqual(loc.range.start, { line: 3, column: 7 });
  assert.deepEqual(loc.range.end, { line: 3, column: 11 });
  // The context may span lines (blocks). Emacs matches by "does the preceding text end with this context"
  assert.equal(loc.context.before, "# 見出し\n\nこの文には、");
  assert.equal(loc.context.after, "があります。\n\n別の段落です。");
  assert.equal(loc.selection, "独自の語");
});

test("block when the same text occurs several times in the block (no guessing)", () => {
  const text = "foo と bar と foo と baz";
  const loc = locate(text, 0, "foo");
  assert.equal(loc.precision, "block");
  assert.equal(loc.expect, text);
  assert.deepEqual(loc.range.start, { line: 1, column: 1 });
});

test("exact when the text occurs once in the targeted block, even if it appears in other blocks", () => {
  const text = "foo はここ\n\nfoo はここにも";
  const loc = locate(text, 1, "foo");
  assert.equal(loc.precision, "exact");
  assert.deepEqual(loc.range.start, { line: 3, column: 1 });
});

test("block when the visible text differs from the source Markdown (spanning emphasis or links)", () => {
  const text = "これは **強調** です";
  const loc = locate(text, 0, "これは 強調 です"); // ** is gone in the rendered text
  assert.equal(loc.precision, "block");
  assert.equal(loc.expect, text);
});

test("exact when only the inside of emphasis is selected", () => {
  const text = "これは **強調** です";
  const loc = locate(text, 0, "強調");
  assert.equal(loc.precision, "exact");
  // "これは **" is 6 characters, so "強調" starts at column 7
  assert.deepEqual(loc.range.start, { line: 1, column: 7 });
});

test("block (the whole block) when there is no selection", () => {
  const loc = locate("一行目\n二行目", 0, "");
  assert.equal(loc.precision, "block");
  assert.deepEqual(loc.range.end, { line: 2, column: 4 });
  assert.equal(loc.expect, "一行目\n二行目");
});

test("whitespace around the selection is ignored", () => {
  const loc = locate("a bb c", 0, "  bb \n");
  assert.equal(loc.precision, "exact");
  assert.equal(loc.expect, "bb");
});

test("CRLF documents: lines and columns do not count CR, and expect is normalized to LF", () => {
  const text = "一行目\r\n二行目\r\n\r\n三行目";
  const b = { start: 0, end: text.indexOf("\r\n\r\n") };
  const loc = locateInSource({
    path: "a.md",
    text,
    version: 1,
    blockStart: b.start,
    blockEnd: b.end,
    selection: "",
  });
  assert.equal(loc.expect, "一行目\n二行目");
  assert.deepEqual(loc.range.end, { line: 2, column: 4 });
  const exact = locateInSource({
    path: "a.md",
    text,
    version: 1,
    blockStart: b.start,
    blockEnd: b.end,
    selection: "二行目",
  });
  assert.deepEqual(exact.range.start, { line: 2, column: 1 });
});

test("even on lines with emoji, the column (code points) matches Emacs' character count", () => {
  const text = "😀😀 target 😀";
  const loc = locate(text, 0, "target");
  assert.equal(loc.precision, "exact");
  assert.deepEqual(loc.range.start, { line: 1, column: 4 });
  assert.deepEqual(loc.range.end, { line: 1, column: 10 });
});

test("a long expect is cut to the first 500 code points and truncated is set", () => {
  const text = "あ".repeat(EXPECT_LIMIT + 50);
  const loc = locate(text, 0, "");
  assert.equal(Array.from(loc.expect).length, EXPECT_LIMIT);
  assert.equal(loc.expectTruncated, true);
  assert.deepEqual(loc.range.end, { line: 1, column: EXPECT_LIMIT + 51 });
});

test("surrounding context does not split a surrogate pair", () => {
  const text = "😀".repeat(CONTEXT_LENGTH) + "X" + "😀".repeat(CONTEXT_LENGTH);
  const loc = locate(text, 0, "X");
  for (const s of [loc.context.before, loc.context.after]) {
    assert.doesNotMatch(s, /[\ud800-\udbff]$|^[\udc00-\udfff]/);
  }
});

test("uniqueMatch: none, one, several (including overlaps)", () => {
  assert.equal(uniqueMatch("abc", "x"), null);
  assert.equal(uniqueMatch("abc", "b"), 1);
  assert.equal(uniqueMatch("aaa", "aa"), null); // 2 overlapping places
  assert.equal(uniqueMatch("abc", ""), null);
});
