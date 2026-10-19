// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

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

test("keyName: letters with modifiers are derived from code (even if Option changes the character)", () => {
  assert.equal(keyName(ev({ key: "f", code: "KeyF", ctrlKey: true })), "C-f");
  assert.equal(keyName(ev({ key: "ƒ", code: "KeyF", altKey: true })), "M-f");
  assert.equal(keyName(ev({ key: "[", code: "BracketLeft", metaKey: true })), "s-[");
  assert.equal(keyName(ev({ key: "Tab", code: "Tab", shiftKey: true })), "S-TAB");
  assert.equal(keyName(ev({ key: "Enter", code: "Enter" })), "RET");
  assert.equal(keyName(ev({ key: "Control", ctrlKey: true })), null);
});

test("keyName: symbols with Option (Meta) are derived from the physical key (M-< and M->)", () => {
  // On macOS, event.key for Option+Shift+, is a different character (≤)
  assert.equal(keyName(ev({ key: "≤", code: "Comma", altKey: true, shiftKey: true })), "M-<");
  assert.equal(keyName(ev({ key: "≥", code: "Period", altKey: true, shiftKey: true })), "M->");
  assert.equal(keyName(ev({ key: "…", code: "Semicolon", altKey: true })), "M-;");
  assert.equal(keyName(ev({ key: "?", code: "Slash", ctrlKey: true, shiftKey: true })), "C-?");
  assert.equal(keyName(ev({ key: "%", code: "Digit5", altKey: true, shiftKey: true })), "M-%");
  assert.equal(keyName(ev({ key: "1", code: "Digit1", altKey: true })), "M-1");
  // Without modifier keys, `key` is used as is (the typed character itself, also for Japanese input and other layouts)
  assert.equal(keyName(ev({ key: "<", code: "Comma", shiftKey: true })), "<");
  // Keys whose symbol Shift does not change (arrows, Tab) get S-
  assert.equal(
    keyName(ev({ key: "ArrowUp", code: "ArrowUp", shiftKey: true, altKey: true })),
    "M-S-up",
  );
});

test("dispatcher: prefixes and unbound keys", () => {
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

test("a keymap conflict throws", () => {
  assert.throws(() => createKeymap({ "C-x": "a", "C-x 2": "b" }));
  assert.throws(() => createKeymap({ "C-x 2": "b", "C-x": "a" }));
});
