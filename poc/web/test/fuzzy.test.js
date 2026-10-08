import test from "node:test";
import assert from "node:assert/strict";
import { fuzzyFilter } from "../fuzzy.js";

const files = ["docs/architecture-evaluation.md", "docs/interaction-model.md", "README.md", "poc/sample/rendering/01-gfm.md", "area0/topic1/group3/doc-00042.md"];

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
