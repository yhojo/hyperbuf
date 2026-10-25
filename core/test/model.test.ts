// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

import assert from "node:assert/strict";
import test from "node:test";
import {
  back,
  backToStart,
  boundaryBelow,
  boundaryRight,
  createModel,
  currentEntry,
  deleteOthers,
  deleteWindow,
  forward,
  forwardToEnd,
  jump,
  killBuffer,
  openBuffer,
  otherWindow,
  removeWindow,
  resizeWindow,
  resolveLink,
  selectedWindow,
  split,
  visit,
  windows,
} from "../src/model.ts";

function setup() {
  const m = createModel();
  for (const p of ["a.md", "b.md", "c.md"]) openBuffer(m, p, `# ${p}\n`);
  visit(m, selectedWindow(m), "a.md");
  return m;
}

const paths = (w: { history: { path: string }[] }) => w.history.map((e) => e.path);

test("reference history: visit/back/forward and discarding forward history", () => {
  const m = setup();
  const w = selectedWindow(m);
  visit(m, w, "b.md");
  visit(m, w, "c.md");
  assert.equal(currentEntry(w)?.path, "c.md");
  assert.ok(back(m, w));
  assert.equal(currentEntry(w)?.path, "b.md");
  visit(m, w, "a.md", "x");
  assert.equal(w.history.length, 3); // c.md was discarded
  assert.ok(!forward(m, w));
});

test("reference history: jump to the first / last", () => {
  const m = setup();
  const w = selectedWindow(m);
  visit(m, w, "b.md");
  visit(m, w, "c.md");
  assert.ok(!forwardToEnd(m, w)); // already at the end
  assert.ok(backToStart(m, w));
  assert.equal(currentEntry(w)?.path, "a.md");
  assert.ok(!backToStart(m, w)); // already at the start
  assert.ok(forwardToEnd(m, w));
  assert.equal(currentEntry(w)?.path, "c.md");
});

test("consecutive visits to the same reference are not pushed", () => {
  const m = setup();
  const w = selectedWindow(m);
  visit(m, w, "a.md");
  assert.equal(w.history.length, 1);
});

test("MRU is managed separately from the reference history", () => {
  const m = setup();
  const w = selectedWindow(m);
  visit(m, w, "b.md");
  visit(m, w, "c.md");
  back(m, w);
  assert.deepEqual(m.mru.slice(0, 3), ["b.md", "c.md", "a.md"]);
});

test("split: the history is copied and independent afterwards", () => {
  const m = setup();
  const w = selectedWindow(m);
  visit(m, w, "b.md");
  const fresh = split(m, "col");
  assert.equal(windows(m).length, 2);
  assert.equal(m.selected, w.id);
  assert.deepEqual(paths(fresh), ["a.md", "b.md"]);
  visit(m, fresh, "c.md");
  assert.equal(w.history.length, 2);
  const entry = currentEntry(w);
  assert.ok(entry);
  entry.scroll = 120;
  assert.equal(currentEntry(fresh)?.scroll, 0);
});

test("window deletion, isolation and movement", () => {
  const m = setup();
  const w1 = selectedWindow(m);
  const w2 = split(m, "row");
  otherWindow(m);
  const w3 = split(m, "col");
  assert.equal(windows(m).length, 3);
  otherWindow(m);
  otherWindow(m);
  assert.equal(m.selected, w1.id);
  otherWindow(m);
  assert.equal(m.selected, w2.id);
  assert.ok(deleteWindow(m));
  assert.equal(windows(m).length, 2);
  assert.ok(windows(m).includes(w3));
  deleteOthers(m);
  assert.equal(windows(m).length, 1);
  assert.ok(!deleteWindow(m));
});

test("link resolution", () => {
  assert.deepEqual(resolveLink("/p/docs/a.md", "b.md#x"), { path: "/p/docs/b.md", anchor: "x" });
  assert.deepEqual(resolveLink("/p/docs/a.md", "../c.md"), { path: "/p/c.md", anchor: null });
  assert.deepEqual(resolveLink("/p/docs/a.md", "#top"), { path: "/p/docs/a.md", anchor: "top" });
  assert.deepEqual(resolveLink("/p/docs/a.md", "/etc/x.md"), { path: "/etc/x.md", anchor: null });
  assert.deepEqual(resolveLink("/a.md", "../../b.md"), { path: "/b.md", anchor: null });
  assert.deepEqual(resolveLink("/p/a.md", "x%20y.md"), { path: "/p/x y.md", anchor: null });
  assert.deepEqual(resolveLink("/p/a.md", "%E6%97%A5%E6%9C%AC.md#a"), {
    path: "/p/日本.md",
    anchor: "a",
  });
  assert.deepEqual(resolveLink("/p/a.md", "bad%E0%A4.md"), {
    path: "/p/bad%E0%A4.md",
    anchor: null,
  });
  assert.equal(resolveLink("/p/a.md", "https://example.com"), null);
});

test("a relative link from a virtual buffer resolves from its origin directory (or / if none)", () => {
  assert.deepEqual(resolveLink("*search: x @ /p/docs*", "area0/doc.md#line:3"), {
    path: "/p/docs/area0/doc.md",
    anchor: "line:3",
  });
  assert.deepEqual(resolveLink("*Help: keybindings*", "x.md"), { path: "/x.md", anchor: null });
  assert.deepEqual(resolveLink("*search: x @ /p*", "/abs/doc.md"), {
    path: "/abs/doc.md",
    anchor: null,
  });
});

test("removeWindow: removes the given window and moves to a neighbor if selected; the only window cannot be removed", () => {
  const m = createModel();
  const first = selectedWindow(m);
  assert.equal(removeWindow(m, first), false);
  const second = split(m, "row");
  assert.equal(removeWindow(m, second), true);
  assert.equal(windows(m).length, 1);
  assert.equal(m.selected, first.id);
  const third = split(m, "col");
  m.selected = third.id;
  assert.equal(removeWindow(m, third), true);
  assert.equal(m.selected, first.id);
});

test("kill-buffer: removes references to the buffer from every window's history and keeps the current position", () => {
  const m = setup();
  const w = selectedWindow(m);
  visit(m, w, "b.md");
  visit(m, w, "c.md");
  visit(m, w, "b.md", "x");
  // history: a, b, c, b#x (current)
  const empty = killBuffer(m, "b.md");
  assert.deepEqual(empty, []);
  assert.deepEqual(paths(w), ["a.md", "c.md"]);
  assert.equal(currentEntry(w)?.path, "c.md"); // the current reference was removed, so the previous one is shown
  assert.ok(!m.buffers.has("b.md"));
  assert.ok(!m.mru.includes("b.md"));
  // Removing a non-current reference leaves the current position unchanged
  killBuffer(m, "a.md");
  assert.equal(currentEntry(w)?.path, "c.md");
  assert.deepEqual(paths(w), ["c.md"]);
});

test("kill-buffer: split windows' histories are cleaned up each; returns the windows whose history became empty", () => {
  const m = setup();
  const w = selectedWindow(m);
  const other = split(m, "row"); // history: [a] (duplicated)
  visit(m, other, "b.md"); // other: a, b
  const empty = killBuffer(m, "a.md");
  assert.deepEqual(paths(w), []);
  assert.deepEqual(paths(other), ["b.md"]);
  assert.deepEqual(empty, [w]);
  assert.equal(w.index, -1);
  assert.equal(currentEntry(other)?.path, "b.md");
});

test("kill-buffer: closing a nonexistent buffer does nothing", () => {
  const m = setup();
  const w = selectedWindow(m);
  assert.deepEqual(killBuffer(m, "nope.md"), []);
  assert.deepEqual(paths(w), ["a.md"]);
});

test("external open with a position: for the displayed document, only the position is replaced without pushing history", () => {
  const m = setup();
  const w = selectedWindow(m);
  jump(m, w, "a.md", "line:3");
  jump(m, w, "a.md", "line:9");
  assert.equal(w.history.length, 1);
  assert.equal(currentEntry(w)?.anchor, "line:9");
  jump(m, w, "a.md"); // no position: unchanged
  assert.equal(currentEntry(w)?.anchor, "line:9");
  jump(m, w, "b.md", "line:1"); // a different document is pushed as usual
  assert.deepEqual(paths(w), ["a.md", "b.md"]);
});

test("window size: grow, shrink, limits and the mode line boundary", () => {
  const m = setup();
  const top = selectedWindow(m);
  const bottom = split(m, "col");
  assert.equal(resizeWindow(m, top, "row", 0.1), false); // there is no left/right split
  assert.equal(resizeWindow(m, top, "col", 0.2), true);
  assert.ok(Math.abs((m.root.type === "split" ? (m.root.ratio ?? 0) : 0) - 0.7) < 1e-9);
  assert.equal(resizeWindow(m, bottom, "col", 0.2), true); // the lower window grows = the boundary moves up
  assert.ok(Math.abs((m.root.type === "split" ? (m.root.ratio ?? 0) : 0) - 0.5) < 1e-9);
  resizeWindow(m, top, "col", 5);
  assert.equal(m.root.type === "split" ? m.root.ratio : 0, 0.9);
  assert.equal(boundaryBelow(m, top), m.root);
  assert.equal(boundaryBelow(m, bottom), null);
});

test("mode line right edge boundary: in a left/right split, only the left window has it", () => {
  const m = setup();
  const left = selectedWindow(m);
  const right = split(m, "row");
  assert.equal(boundaryRight(m, left), m.root);
  assert.equal(boundaryRight(m, right), null);
  assert.equal(boundaryBelow(m, left), null);
});

test("the selected link is kept on the history entry across back / forward", () => {
  const m = setup();
  const w = selectedWindow(m);
  const a = currentEntry(w);
  assert.ok(a);
  a.link = 1;
  visit(m, w, "b.md");
  assert.equal(currentEntry(w)?.link, undefined);
  back(m, w);
  assert.equal(currentEntry(w)?.link, 1);
});
