// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

import assert from "node:assert/strict";
import test from "node:test";
import {
  back,
  createModel,
  currentEntry,
  deleteOthers,
  deleteWindow,
  forward,
  killBuffer,
  openBuffer,
  otherWindow,
  removeWindow,
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

test("参照履歴: visit/back/forward と先の履歴の破棄", () => {
  const m = setup();
  const w = selectedWindow(m);
  visit(m, w, "b.md");
  visit(m, w, "c.md");
  assert.equal(currentEntry(w)?.path, "c.md");
  assert.ok(back(m, w));
  assert.equal(currentEntry(w)?.path, "b.md");
  visit(m, w, "a.md", "x");
  assert.equal(w.history.length, 3); // c.md は破棄された
  assert.ok(!forward(m, w));
});

test("同じ参照の連続 visit は積まない", () => {
  const m = setup();
  const w = selectedWindow(m);
  visit(m, w, "a.md");
  assert.equal(w.history.length, 1);
});

test("MRU は参照履歴とは別に管理される", () => {
  const m = setup();
  const w = selectedWindow(m);
  visit(m, w, "b.md");
  visit(m, w, "c.md");
  back(m, w);
  assert.deepEqual(m.mru.slice(0, 3), ["b.md", "c.md", "a.md"]);
});

test("分割: 履歴は複製され、以降は独立する", () => {
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

test("window の削除・単独化・移動", () => {
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

test("リンク解決", () => {
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

test("仮想 buffer からの相対リンクは、起点のディレクトリ(なければ /)からになる", () => {
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

test("removeWindow: 指定した window を取り除き、選択中なら隣に移る。唯一の window は取り除けない", () => {
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

test("kill-buffer: どの window の履歴からも、その buffer への参照を取り除き、現在位置を保つ", () => {
  const m = setup();
  const w = selectedWindow(m);
  visit(m, w, "b.md");
  visit(m, w, "c.md");
  visit(m, w, "b.md", "x");
  // 履歴: a, b, c, b#x(現在)
  const empty = killBuffer(m, "b.md");
  assert.deepEqual(empty, []);
  assert.deepEqual(paths(w), ["a.md", "c.md"]);
  assert.equal(currentEntry(w)?.path, "c.md"); // 現在の参照が消えたので、ひとつ前の参照を表示する
  assert.ok(!m.buffers.has("b.md"));
  assert.ok(!m.mru.includes("b.md"));
  // 現在でない参照を消すと、現在位置は、そのまま
  killBuffer(m, "a.md");
  assert.equal(currentEntry(w)?.path, "c.md");
  assert.deepEqual(paths(w), ["c.md"]);
});

test("kill-buffer: 分割した window の履歴も、それぞれ整理される。履歴が空になった window を返す", () => {
  const m = setup();
  const w = selectedWindow(m);
  const other = split(m, "row"); // 履歴: [a](複製)
  visit(m, other, "b.md"); // other: a, b
  const empty = killBuffer(m, "a.md");
  assert.deepEqual(paths(w), []);
  assert.deepEqual(paths(other), ["b.md"]);
  assert.deepEqual(empty, [w]);
  assert.equal(w.index, -1);
  assert.equal(currentEntry(other)?.path, "b.md");
});

test("kill-buffer: ない buffer を閉じても、何も起きない", () => {
  const m = setup();
  const w = selectedWindow(m);
  assert.deepEqual(killBuffer(m, "nope.md"), []);
  assert.deepEqual(paths(w), ["a.md"]);
});
