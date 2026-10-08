import assert from "node:assert/strict";
import test from "node:test";
import {
  back,
  createModel,
  currentEntry,
  deleteOthers,
  deleteWindow,
  forward,
  openBuffer,
  otherWindow,
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
  assert.deepEqual(resolveLink("docs/a.md", "b.md#x"), { path: "docs/b.md", anchor: "x" });
  assert.deepEqual(resolveLink("docs/a.md", "../c.md"), { path: "c.md", anchor: null });
  assert.deepEqual(resolveLink("docs/a.md", "#top"), { path: "docs/a.md", anchor: "top" });
  assert.equal(resolveLink("a.md", "https://example.com"), null);
});

test("仮想 buffer(ディレクトリを持たないパス)からのリンクはルートからの相対になる", () => {
  assert.deepEqual(resolveLink("*search: x*", "area0/doc.md#line:3"), {
    path: "area0/doc.md",
    anchor: "line:3",
  });
});
