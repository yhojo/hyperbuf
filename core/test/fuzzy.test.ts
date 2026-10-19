// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

import assert from "node:assert/strict";
import test from "node:test";
import { fuzzyFilter, matchRanges } from "../src/fuzzy.ts";

const files = [
  "docs/architecture-evaluation.md",
  "docs/interaction-model.md",
  "README.md",
  "poc/sample/rendering/01-gfm.md",
  "area0/topic1/group3/doc-00042.md",
];

test("an empty query returns from the start", () => {
  assert.deepEqual(fuzzyFilter(files, "", 2), files.slice(0, 2));
});

test("a match on the file name beats a match on the directory name", () => {
  assert.equal(fuzzyFilter(files, "model")[0], "docs/interaction-model.md");
  assert.equal(fuzzyFilter(files, "readme")[0], "README.md");
});

test("all whitespace-separated words must be included", () => {
  assert.deepEqual(fuzzyFilter(files, "docs arch"), ["docs/architecture-evaluation.md"]);
  assert.deepEqual(fuzzyFilter(files, "docs zzz"), []);
});

test("scattered matches", () => {
  assert.equal(fuzzyFilter(files, "inmo")[0], "docs/interaction-model.md");
  assert.equal(fuzzyFilter(files, "g3d42")[0], "area0/topic1/group3/doc-00042.md");
});

test("matched ranges (for highlighting): prefer the file name, handle per-word and scattered matches, and merge", () => {
  assert.deepEqual(matchRanges("docs/interaction-model.md", "model"), [[17, 22]]);
  assert.deepEqual(matchRanges("docs/model/model.md", "model"), [[11, 16]]); // the file name side
  assert.deepEqual(matchRanges("docs/interaction-model.md", "docs model"), [
    [0, 4],
    [17, 22],
  ]);
  assert.deepEqual(matchRanges("docs/interaction-model.md", "inmo"), [
    [5, 7],
    [17, 19],
  ]);
  assert.deepEqual(matchRanges("abc", "ab bc"), [[0, 3]]); // overlapping ranges are merged
  assert.deepEqual(matchRanges("abc", ""), []);
  assert.deepEqual(matchRanges("abc", "zzz"), []);
});
