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

test("空の問い合わせは先頭から返す", () => {
  assert.deepEqual(fuzzyFilter(files, "", 2), files.slice(0, 2));
});

test("ファイル名への一致を、ディレクトリ名への一致より優先する", () => {
  assert.equal(fuzzyFilter(files, "model")[0], "docs/interaction-model.md");
  assert.equal(fuzzyFilter(files, "readme")[0], "README.md");
});

test("空白区切りの語はすべて含む必要がある", () => {
  assert.deepEqual(fuzzyFilter(files, "docs arch"), ["docs/architecture-evaluation.md"]);
  assert.deepEqual(fuzzyFilter(files, "docs zzz"), []);
});

test("飛び飛びの一致", () => {
  assert.equal(fuzzyFilter(files, "inmo")[0], "docs/interaction-model.md");
  assert.equal(fuzzyFilter(files, "g3d42")[0], "area0/topic1/group3/doc-00042.md");
});

test("一致した範囲(強調表示用): ファイル名を優先し、語ごと・飛び飛びにも対応し、まとめる", () => {
  assert.deepEqual(matchRanges("docs/interaction-model.md", "model"), [[17, 22]]);
  assert.deepEqual(matchRanges("docs/model/model.md", "model"), [[11, 16]]); // ファイル名の側
  assert.deepEqual(matchRanges("docs/interaction-model.md", "docs model"), [
    [0, 4],
    [17, 22],
  ]);
  assert.deepEqual(matchRanges("docs/interaction-model.md", "inmo"), [
    [5, 7],
    [17, 19],
  ]);
  assert.deepEqual(matchRanges("abc", "ab bc"), [[0, 3]]); // 重なる範囲は、まとめる
  assert.deepEqual(matchRanges("abc", ""), []);
  assert.deepEqual(matchRanges("abc", "zzz"), []);
});
