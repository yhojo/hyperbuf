// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

import assert from "node:assert/strict";
import { test } from "node:test";
import { parseVirtualPath, uniquifyNames, virtualPath } from "../src/names.ts";

const HOME = "/Users/me";
const names = (...paths: string[]) => uniquifyNames(paths, HOME);

test("without a collision, just the file name", () => {
  const n = names("/Users/me/work/a/docs/design.md", "/Users/me/work/a/docs/other.md");
  assert.equal(n.get("/Users/me/work/a/docs/design.md"), "design.md");
});

test("identical names get the smallest directory levels that tell them apart (post-forward-angle-brackets)", () => {
  const n = names("/Users/me/work/a/docs/README.md", "/Users/me/work/a/emacs/README.md");
  assert.equal(n.get("/Users/me/work/a/docs/README.md"), "README.md<docs>");
  assert.equal(n.get("/Users/me/work/a/emacs/README.md"), "README.md<emacs>");
});

test("if the parents have the same name, extend further up", () => {
  const n = names(
    "/Users/me/a/docs/README.md",
    "/Users/me/b/docs/README.md",
    "/Users/me/b/src/README.md",
  );
  assert.equal(n.get("/Users/me/a/docs/README.md"), "README.md<a/docs>");
  assert.equal(n.get("/Users/me/b/docs/README.md"), "README.md<b/docs>");
  assert.equal(n.get("/Users/me/b/src/README.md"), "README.md<src>");
});

test("directly under the host's home is ~, directly under the root is /", () => {
  const n = names("/Users/me/README.md", "/Users/me/docs/README.md", "/README.md");
  assert.equal(n.get("/Users/me/README.md"), "README.md<~>");
  assert.equal(n.get("/Users/me/docs/README.md"), "README.md<docs>");
  assert.equal(n.get("/README.md"), "README.md</>");
});

test("when a collision disappears after closing, the name reverts (names are dynamic)", () => {
  assert.equal(names("/x/a/R.md", "/x/b/R.md").get("/x/a/R.md"), "R.md<a>");
  assert.equal(names("/x/a/R.md").get("/x/a/R.md"), "R.md");
});

test("virtual buffers: always append the origin if present; those without one stay as is", () => {
  const search = virtualPath("search: foo", "/Users/me/work/docs");
  const help = virtualPath("Help: keybindings");
  const n = names(search, help, "/Users/me/work/docs/a.md");
  assert.equal(n.get(search), "*search: foo*<docs>");
  assert.equal(n.get(help), "*Help: keybindings*");
  assert.deepEqual(parseVirtualPath(search), { label: "search: foo", dir: "/Users/me/work/docs" });
  assert.deepEqual(parseVirtualPath(help), { label: "Help: keybindings" });
});

test("the same search word with different origins is told apart by origin", () => {
  const a = virtualPath("search: foo", "/p/x/docs");
  const b = virtualPath("search: foo", "/p/y/docs");
  const n = names(a, b);
  assert.equal(n.get(a), "*search: foo*<x/docs>");
  assert.equal(n.get(b), "*search: foo*<y/docs>");
});
