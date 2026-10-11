// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

import assert from "node:assert/strict";
import { test } from "node:test";
import {
  abbreviateHome,
  basename,
  dirname,
  expandHome,
  isInside,
  joinPath,
  normalizePath,
  resolveInput,
} from "../src/paths.ts";

test("normalizePath: . と .. と重複した / を解決し、/ より上へは行かない", () => {
  assert.equal(normalizePath("/a/b/../c/./d//e"), "/a/c/d/e");
  assert.equal(normalizePath("/../../x"), "/x");
  assert.equal(normalizePath("/"), "/");
  assert.equal(normalizePath("/a/.."), "/");
});

test("dirname / basename / joinPath", () => {
  assert.equal(dirname("/a/b/c.md"), "/a/b");
  assert.equal(dirname("/c.md"), "/");
  assert.equal(basename("/a/b/c.md"), "c.md");
  assert.equal(joinPath("/a/b", "../c.md"), "/a/c.md");
  assert.equal(joinPath("/a/b", "/x/y.md"), "/x/y.md");
});

test("expandHome / abbreviateHome", () => {
  assert.equal(expandHome("~", "/Users/me"), "/Users/me");
  assert.equal(expandHome("~/docs", "/Users/me"), "/Users/me/docs");
  assert.equal(expandHome("~other/x", "/Users/me"), "~other/x");
  assert.equal(abbreviateHome("/Users/me/docs/a.md", "/Users/me"), "~/docs/a.md");
  assert.equal(abbreviateHome("/Users/me", "/Users/me"), "~");
  assert.equal(abbreviateHome("/Users/mex/a.md", "/Users/me"), "/Users/mex/a.md");
});

test("resolveInput: 相対は base から、~ は展開、末尾の / は残す", () => {
  assert.equal(resolveInput("sub/a.md", "/base", "/h"), "/base/sub/a.md");
  assert.equal(resolveInput("~/x/", "/base", "/h"), "/h/x/");
  assert.equal(resolveInput("../y.md", "/base/z", "/h"), "/base/y.md");
  assert.equal(resolveInput("/abs/./q.md", "/base", "/h"), "/abs/q.md");
  assert.equal(resolveInput("/", "/base", "/h"), "/");
});

test("isInside: 区切りの境界で判定する", () => {
  assert.equal(isInside("/tmp/a.md", "/tmp"), true);
  assert.equal(isInside("/tmp", "/tmp"), true);
  assert.equal(isInside("/tmp2/a.md", "/tmp"), false);
  assert.equal(isInside("/anything", "/"), true);
});
