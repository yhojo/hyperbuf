import assert from "node:assert/strict";
import test from "node:test";
import { createDispatcher, createKeymap, keyName } from "../src/keys.ts";
import type { KeyEventLike } from "../src/keys.ts";

const ev = (o: Partial<KeyEventLike>): KeyEventLike => ({
  key: "",
  code: "",
  ctrlKey: false,
  altKey: false,
  metaKey: false,
  shiftKey: false,
  ...o,
});

test("keyName: 修飾キー付き英字は code から求める(Option で文字が変わっても)", () => {
  assert.equal(keyName(ev({ key: "f", code: "KeyF", ctrlKey: true })), "C-f");
  assert.equal(keyName(ev({ key: "ƒ", code: "KeyF", altKey: true })), "M-f");
  assert.equal(keyName(ev({ key: "[", code: "BracketLeft", metaKey: true })), "s-[");
  assert.equal(keyName(ev({ key: "Tab", code: "Tab", shiftKey: true })), "S-TAB");
  assert.equal(keyName(ev({ key: "Enter", code: "Enter" })), "RET");
  assert.equal(keyName(ev({ key: "Control", ctrlKey: true })), null);
});

test("keyName: Option(Meta)つきの記号は、物理キーから求める(M-< と M->)", () => {
  // macOS では、Option+Shift+, の event.key は、別の文字(≤)になる
  assert.equal(keyName(ev({ key: "≤", code: "Comma", altKey: true, shiftKey: true })), "M-<");
  assert.equal(keyName(ev({ key: "≥", code: "Period", altKey: true, shiftKey: true })), "M->");
  assert.equal(keyName(ev({ key: "…", code: "Semicolon", altKey: true })), "M-;");
  assert.equal(keyName(ev({ key: "?", code: "Slash", ctrlKey: true, shiftKey: true })), "C-?");
  assert.equal(keyName(ev({ key: "%", code: "Digit5", altKey: true, shiftKey: true })), "M-%");
  assert.equal(keyName(ev({ key: "1", code: "Digit1", altKey: true })), "M-1");
  // 修飾キーがなければ、`key` のまま(日本語入力・他の配列でも、入力した文字そのもの)
  assert.equal(keyName(ev({ key: "<", code: "Comma", shiftKey: true })), "<");
  // Shift が、記号を変えないキー(矢印・Tab)には、S- が付く
  assert.equal(
    keyName(ev({ key: "ArrowUp", code: "ArrowUp", shiftKey: true, altKey: true })),
    "M-S-up",
  );
});

test("ディスパッチャ: プレフィックスと未割り当て", () => {
  const d = createDispatcher(
    createKeymap({ "C-x 2": "split-below", "C-x C-f": "find-file", "C-f": "forward" }),
  );
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
