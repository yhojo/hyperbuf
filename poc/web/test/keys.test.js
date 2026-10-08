import test from "node:test";
import assert from "node:assert/strict";
import { keyName, createKeymap, createDispatcher } from "../keys.js";

const ev = (o) => ({ key: "", code: "", ctrlKey: false, altKey: false, metaKey: false, shiftKey: false, ...o });

test("keyName: 修飾キー付き英字は code から求める(Option で文字が変わっても)", () => {
  assert.equal(keyName(ev({ key: "f", code: "KeyF", ctrlKey: true })), "C-f");
  assert.equal(keyName(ev({ key: "ƒ", code: "KeyF", altKey: true })), "M-f");
  assert.equal(keyName(ev({ key: "[", code: "BracketLeft", metaKey: true })), "s-[");
  assert.equal(keyName(ev({ key: "Tab", code: "Tab", shiftKey: true })), "S-TAB");
  assert.equal(keyName(ev({ key: "Enter", code: "Enter" })), "RET");
  assert.equal(keyName(ev({ key: "Control", ctrlKey: true })), null);
});

test("ディスパッチャ: プレフィックスと未割り当て", () => {
  const d = createDispatcher(createKeymap({ "C-x 2": "split-below", "C-x C-f": "find-file", "C-f": "forward" }));
  assert.deepEqual(d.feed("C-x"), { type: "prefix", pending: ["C-x"] });
  assert.deepEqual(d.feed("2"), { type: "command", command: "split-below" });
  assert.deepEqual(d.feed("C-f"), { type: "command", command: "forward" });
  d.feed("C-x");
  assert.deepEqual(d.feed("z"), { type: "unbound", keys: ["C-x", "z"] });
  assert.deepEqual(d.pending, []);
});

test("キーマップの競合は例外", () => {
  assert.throws(() => createKeymap({ "C-x": "a", "C-x 2": "b" }));
  assert.throws(() => createKeymap({ "C-x 2": "b", "C-x": "a" }));
});
