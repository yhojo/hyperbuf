import assert from "node:assert/strict";
import { test } from "node:test";
import { createModel, selectedWindow, split, visit, windows } from "../src/model.ts";
import {
  MAX_HISTORY,
  parseSnapshot,
  referencedPaths,
  restoredSelection,
  restoreModel,
  takeSnapshot,
} from "../src/session.ts";

const all = (...paths: string[]): ReadonlySet<string> => new Set(paths);

function sample() {
  const model = createModel();
  visit(model, selectedWindow(model), "a.md");
  visit(model, selectedWindow(model), "b.md", "sec");
  const fresh = split(model, "row");
  visit(model, fresh, "c.md");
  fresh.history[fresh.index]!.scroll = 120;
  model.selected = fresh.id;
  return model;
}

test("保存して復元すると、配置・履歴・位置・選択・最近使った順が戻る", () => {
  const model = sample();
  const snap = takeSnapshot(model);
  assert.ok(snap);
  const restored = restoreModel(
    parseSnapshot(JSON.parse(JSON.stringify(snap)))!,
    all("a.md", "b.md", "c.md"),
  )!;
  assert.deepEqual(
    windows(restored).map((w) => [w.id, w.index, w.history]),
    windows(model).map((w) => [w.id, w.index, w.history]),
  );
  assert.equal(restored.selected, model.selected);
  assert.deepEqual(restored.mru, model.mru);
  assert.equal(restored.root.type, "split");
  assert.ok(restored.winSeq >= model.winSeq);
});

test("仮想 buffer(*search: …*)は保存しない", () => {
  const model = createModel();
  const win = selectedWindow(model);
  visit(model, win, "a.md");
  visit(model, win, "*search: x*");
  const snap = takeSnapshot(model)!;
  const node = snap.root;
  assert.equal(node.type, "leaf");
  if (node.type === "leaf") {
    assert.deepEqual(
      node.history.map((e) => e.path),
      ["a.md"],
    );
    assert.equal(node.index, 0);
  }
  assert.deepEqual(snap.mru, ["a.md"]);
});

test("保存できる履歴がない window は、分割をたたむ。全部なければ null", () => {
  const model = createModel();
  const win = selectedWindow(model);
  visit(model, win, "a.md");
  split(model, "col"); // 複製された履歴を持つ
  const other = windows(model)[1]!;
  other.history = [{ path: "*search: x*", anchor: null, scroll: 0 }];
  other.index = 0;
  assert.equal(takeSnapshot(model)!.root.type, "leaf");
  const empty = createModel();
  visit(empty, selectedWindow(empty), "*search: x*");
  assert.equal(takeSnapshot(empty), null);
});

test("なくなった文書は、履歴から外れ、現在位置は前の参照になる", () => {
  const model = sample();
  const restored = restoreModel(takeSnapshot(model)!, all("a.md", "c.md"))!;
  const left = windows(restored)[0]!;
  assert.deepEqual(
    left.history.map((e) => e.path),
    ["a.md"],
  );
  assert.equal(left.index, 0);
  assert.deepEqual(restored.mru.includes("b.md"), false);
});

test("文書がすべてなくなれば null、片方の window だけ残れば分割をたたむ", () => {
  const snap = takeSnapshot(sample())!;
  assert.equal(restoreModel(snap, all()), null);
  const one = restoreModel(snap, all("c.md"))!;
  assert.equal(one.root.type, "leaf");
  assert.equal(one.selected, windows(one)[0]!.id);
});

test("履歴が長いときは、現在位置を含む MAX_HISTORY 件に切る", () => {
  const model = createModel();
  const win = selectedWindow(model);
  for (let i = 0; i < 250; i++) visit(model, win, `d${i}.md`);
  win.index = 40;
  const node = takeSnapshot(model)!.root;
  assert.equal(node.type, "leaf");
  if (node.type === "leaf") {
    assert.equal(node.history.length, MAX_HISTORY);
    assert.equal(node.history[node.index]!.path, "d40.md");
  }
});

test("壊れたデータは、使わない", () => {
  const good = JSON.parse(JSON.stringify(takeSnapshot(sample())));
  assert.ok(parseSnapshot(good));
  const bad = (mutate: (s: any) => void) => {
    const copy = JSON.parse(JSON.stringify(good));
    mutate(copy);
    return parseSnapshot(copy);
  };
  assert.equal(parseSnapshot(null), null);
  assert.equal(parseSnapshot("x"), null);
  assert.equal(
    bad((s) => (s.version = 2)),
    null,
  );
  assert.equal(
    bad((s) => (s.root.type = "other")),
    null,
  );
  assert.equal(
    bad((s) => (s.root.dir = "diagonal")),
    null,
  );
  assert.equal(
    bad((s) => (s.root.children[0].history[0].path = 5)),
    null,
  );
  assert.equal(
    bad((s) => (s.root.children[0].history[0].scroll = -1)),
    null,
  );
  assert.equal(
    bad((s) => (s.root.children[0].history[0].scroll = "1")),
    null,
  );
  assert.equal(
    bad((s) => (s.root.children[1].id = s.root.children[0].id)),
    null,
  );
  assert.equal(
    bad((s) => (s.mru = [1])),
    null,
  );
  assert.equal(
    bad((s) => (s.mru = Array(201).fill("a.md"))),
    null,
  );
  assert.equal(
    bad((s) => (s.winSeq = 0)),
    null,
  );
});

test("選択中の window がなければ、先頭の window", () => {
  const snap = takeSnapshot(sample())!;
  snap.selected = 999;
  const restored = restoreModel(
    parseSnapshot(JSON.parse(JSON.stringify(snap)))!,
    all("a.md", "b.md", "c.md"),
  )!;
  assert.equal(restored.selected, windows(restored)[0]!.id);
});

test("referencedPaths: 履歴にある文書を重複なく返す", () => {
  const restored = restoreModel(takeSnapshot(sample())!, all("a.md", "b.md", "c.md"))!;
  assert.deepEqual(referencedPaths(restored).sort(), ["a.md", "b.md", "c.md"]);
});

const selectionIn = (model: ReturnType<typeof sample>) => {
  const win = windows(model)[1]!;
  return { win: win.id, path: "c.md", start: 10, end: 15, text: "hello" };
};

test("選択範囲は、保存して復元できる。window や文書が変わっていれば使わない", () => {
  const model = sample();
  const snap = takeSnapshot(model, selectionIn(model))!;
  const parsed = parseSnapshot(JSON.parse(JSON.stringify(snap)))!;
  assert.deepEqual(parsed.selection, selectionIn(model));
  const restored = restoreModel(parsed, all("a.md", "b.md", "c.md"))!;
  assert.deepEqual(restoredSelection(parsed, restored), selectionIn(model));
  // c.md がなくなると、その window の現在の文書が変わる(または、window ごとなくなる)ので、使わない
  const without = restoreModel(parsed, all("a.md", "b.md"))!;
  assert.equal(restoredSelection(parsed, without), null);
});

test("選択範囲だけが壊れていても、ほかは復元できる", () => {
  const model = sample();
  const good = JSON.parse(JSON.stringify(takeSnapshot(model, selectionIn(model))));
  const only = (mutate: (s: any) => void) => {
    const copy = JSON.parse(JSON.stringify(good));
    mutate(copy);
    return parseSnapshot(copy);
  };
  for (const mutate of [
    (s: any) => (s.selection.start = -1),
    (s: any) => (s.selection.end = s.selection.start),
    (s: any) => (s.selection.text = "hi"),
    (s: any) => (s.selection.win = 999),
    (s: any) => (s.selection.path = ""),
    (s: any) => (s.selection.text = "x".repeat(5000)),
    (s: any) => (s.selection = "x"),
  ]) {
    const parsed = only(mutate);
    assert.ok(parsed, "スナップショット自体は使える");
    assert.equal(parsed.selection, undefined);
  }
});

test("存在しない window や仮想 buffer の選択範囲は、保存しない", () => {
  const model = sample();
  assert.equal(takeSnapshot(model, { ...selectionIn(model), win: 999 })!.selection, undefined);
  assert.equal(
    takeSnapshot(model, { ...selectionIn(model), path: "*search: x*" })!.selection,
    undefined,
  );
});
