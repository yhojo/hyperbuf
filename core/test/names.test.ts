// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

import assert from "node:assert/strict";
import { test } from "node:test";
import { parseVirtualPath, uniquifyNames, virtualPath } from "../src/names.ts";

const HOME = "/Users/me";
const names = (...paths: string[]) => uniquifyNames(paths, HOME);

test("衝突しなければ、ファイル名だけ", () => {
  const n = names("/Users/me/work/a/docs/design.md", "/Users/me/work/a/docs/other.md");
  assert.equal(n.get("/Users/me/work/a/docs/design.md"), "design.md");
});

test("同じ名前は、区別がつく最小の階層を足す(post-forward-angle-brackets)", () => {
  const n = names("/Users/me/work/a/docs/README.md", "/Users/me/work/a/emacs/README.md");
  assert.equal(n.get("/Users/me/work/a/docs/README.md"), "README.md<docs>");
  assert.equal(n.get("/Users/me/work/a/emacs/README.md"), "README.md<emacs>");
});

test("親が同じ名前なら、さらに上へ伸ばす", () => {
  const n = names(
    "/Users/me/a/docs/README.md",
    "/Users/me/b/docs/README.md",
    "/Users/me/b/src/README.md",
  );
  assert.equal(n.get("/Users/me/a/docs/README.md"), "README.md<a/docs>");
  assert.equal(n.get("/Users/me/b/docs/README.md"), "README.md<b/docs>");
  assert.equal(n.get("/Users/me/b/src/README.md"), "README.md<src>");
});

test("ホスト直下は ~、ルート直下は /", () => {
  const n = names("/Users/me/README.md", "/Users/me/docs/README.md", "/README.md");
  assert.equal(n.get("/Users/me/README.md"), "README.md<~>");
  assert.equal(n.get("/Users/me/docs/README.md"), "README.md<docs>");
  assert.equal(n.get("/README.md"), "README.md</>");
});

test("閉じて衝突がなくなれば、名前は元に戻る(名前は動的)", () => {
  assert.equal(names("/x/a/R.md", "/x/b/R.md").get("/x/a/R.md"), "R.md<a>");
  assert.equal(names("/x/a/R.md").get("/x/a/R.md"), "R.md");
});

test("仮想バッファ: 起点があれば常に添える。起点のないものは、そのまま", () => {
  const search = virtualPath("search: foo", "/Users/me/work/docs");
  const help = virtualPath("Help: keybindings");
  const n = names(search, help, "/Users/me/work/docs/a.md");
  assert.equal(n.get(search), "*search: foo*<docs>");
  assert.equal(n.get(help), "*Help: keybindings*");
  assert.deepEqual(parseVirtualPath(search), { label: "search: foo", dir: "/Users/me/work/docs" });
  assert.deepEqual(parseVirtualPath(help), { label: "Help: keybindings" });
});

test("起点が違う同じ検索語は、起点で区別できる", () => {
  const a = virtualPath("search: foo", "/p/x/docs");
  const b = virtualPath("search: foo", "/p/y/docs");
  const n = names(a, b);
  assert.equal(n.get(a), "*search: foo*<x/docs>");
  assert.equal(n.get(b), "*search: foo*<y/docs>");
});
