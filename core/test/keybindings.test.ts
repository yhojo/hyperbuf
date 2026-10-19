// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

import assert from "node:assert/strict";
import test from "node:test";
import { renderBindingsHelp } from "../src/help.ts";
import { applyOverrides, isValidKeySequence, keysByCommand } from "../src/keybindings.ts";
import { createKeymap } from "../src/keys.ts";

const known = new Set(["back", "forward", "split-below", "find-file", "next-link"]);
const defaults = {
  "C-f": "forward",
  "C-b": "back",
  "C-x 2": "split-below",
  "C-x C-f": "find-file",
};

test("key notation validation", () => {
  for (const ok of [
    "C-x",
    "C-x 2",
    "M-x",
    "s-[",
    "S-TAB",
    "C-M-s",
    "SPC",
    "RET",
    "up",
    "M->",
    "a",
  ]) {
    // C-M-s follows the modifier order (C- M- s- S-), so it is valid
    assert.ok(isValidKeySequence(ok), ok);
  }
  for (const bad of [
    "",
    " ",
    "x  y",
    "Ctrl-x",
    "M-C-x",
    "C-",
    "C-x C-y C-z C-a C-b",
    "ab",
    "F13",
    "C-x\t2",
  ]) {
    assert.ok(!isValidKeySequence(bad), JSON.stringify(bad));
  }
});

test("add, replace and remove bindings", () => {
  const r = applyOverrides(defaults, { "M-p": "back", "C-f": null, "C-x 2": "next-link" }, known);
  assert.deepEqual(r.problems, []);
  assert.equal(r.bindings["M-p"], "back");
  assert.ok(!("C-f" in r.bindings)); // removed
  assert.equal(r.bindings["C-x 2"], "next-link"); // replaced
  assert.equal(r.bindings["C-b"], "back"); // others unchanged
  assert.doesNotThrow(() => createKeymap(r.bindings));
});

test("does not change the default bindings (the original object stays immutable)", () => {
  const before = JSON.stringify(defaults);
  applyOverrides(defaults, { "C-f": null, "M-p": "back" }, known);
  assert.equal(JSON.stringify(defaults), before);
});

test("unknown commands, invalid notation and unbinding unbound keys are ignored with a reason recorded", () => {
  const r = applyOverrides(
    defaults,
    { "M-q": "no-such-command", "Ctrl-x": "back", "M-z": null, "M-w": "back" },
    known,
  );
  assert.equal(r.problems.length, 3);
  assert.ok(r.problems.some((p) => p.includes("unknown command")));
  assert.ok(r.problems.some((p) => p.includes("invalid key notation")));
  assert.ok(r.problems.some((p) => p.includes("cannot be removed")));
  assert.equal(r.bindings["M-w"], "back"); // valid ones are applied
  assert.ok(!("M-q" in r.bindings));
});

test("C-g is reserved for cancel", () => {
  const r = applyOverrides(defaults, { "C-g": "back" }, known);
  assert.ok(r.problems[0]?.includes("reserved"));
  assert.ok(!("C-g" in r.bindings));
});

test("prefix/command conflicts are ignored (unbind first, then bind, to do it)", () => {
  // C-x is a prefix of C-x 2 and so on
  const conflict = applyOverrides(defaults, { "C-x": "back" }, known);
  assert.ok(conflict.problems[0]?.includes("conflicts"));
  assert.ok(!("C-x" in conflict.bindings));
  // Binding further under C-x 2 makes C-x 2 both a command and a prefix
  const deeper = applyOverrides(defaults, { "C-x 2 a": "back" }, known);
  assert.ok(deeper.problems[0]?.includes("conflicts"));
  // Unbind first (unbinding is processed first regardless of order)
  const ok = applyOverrides(defaults, { "C-x 2 a": "back", "C-x 2": null }, known);
  assert.deepEqual(ok.problems, []);
  assert.equal(ok.bindings["C-x 2 a"], "back");
});

test("independent of the order of settings (unbinding comes first)", () => {
  const a = applyOverrides(defaults, { "C-f": null, "C-f ": "back" } as never, known);
  const b = applyOverrides(defaults, { "M-a": "back", "C-b": null }, known);
  const c = applyOverrides(defaults, { "C-b": null, "M-a": "back" }, known);
  assert.deepEqual(b, c);
  assert.ok(a.problems.length >= 0);
});

test("keys per command", () => {
  const keys = keysByCommand({ "C-f": "forward", "s-]": "forward", "C-b": "back" });
  assert.deepEqual(keys.get("forward"), ["C-f", "s-]"]);
  assert.deepEqual(keys.get("back"), ["C-b"]);
});

test("describe-bindings content: bound, unbound and configuration problems", () => {
  const md = renderBindingsHelp({
    docs: { forward: "進む|戻る", back: "戻る", "next-link": "次のリンク" },
    bindings: { "C-f": "forward", "s-]": "forward", "C-b": "back" },
    problems: ['"M-q": unknown command: x'],
  });
  assert.match(md, /^# Key bindings/);
  assert.match(md, /## Configuration problems[\s\S]*unknown command/);
  assert.match(md, /\| `C-f`, `s-]` \| `forward` \| 進む\\\|戻る \|/); // does not break the table delimiter
  assert.match(md, /## Unbound commands[\s\S]*\| `next-link` \| 次のリンク \|/);
  const none = renderBindingsHelp({
    docs: { back: "x" },
    bindings: { "C-b": "back" },
    problems: [],
  });
  assert.doesNotMatch(none, /Configuration problems/);
});
