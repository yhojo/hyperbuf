// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

import assert from "node:assert/strict";
import test from "node:test";
import { COMMAND_NAMES } from "../src/ui/commands.ts";
import { DEFAULT_BINDINGS, defaultKeymap } from "../src/ui/keymap.ts";

test("the default key bindings build without conflicts", () => {
  assert.doesNotThrow(() => defaultKeymap());
});

test("every command a key binding points to is defined", () => {
  const names = new Set<string>(COMMAND_NAMES);
  for (const [keys, command] of Object.entries(DEFAULT_BINDINGS)) {
    assert.ok(names.has(command), `${keys} → ${command} is an undefined command`);
  }
});

test("Back / Forward are bound to C-b / C-f and Cmd+[ / Cmd+] (agreed)", () => {
  assert.equal(DEFAULT_BINDINGS["C-b"], "back");
  assert.equal(DEFAULT_BINDINGS["C-f"], "forward");
  assert.equal(DEFAULT_BINDINGS["s-["], "back");
  assert.equal(DEFAULT_BINDINGS["s-]"], "forward");
});

test("command names offered by M-x have no duplicates", () => {
  assert.equal(new Set(COMMAND_NAMES).size, COMMAND_NAMES.length);
});

test("user settings can be layered over the default bindings (including the describe-bindings binding)", async () => {
  const { resolveBindings } = await import("../src/ui/keymap.ts");
  const r = resolveBindings({ "M-p": "back", "C-f": null, "C-x 9": "no-such" });
  assert.equal(r.bindings["M-p"], "back");
  assert.ok(!("C-f" in r.bindings));
  assert.equal(r.problems.length, 1);
  assert.equal(resolveBindings(undefined).problems.length, 0);
});

test("C-h b is describe-bindings", () => {
  assert.equal(DEFAULT_BINDINGS["C-h b"], "describe-bindings");
});

test("every command has a description (COMMAND_DOCS detects omissions by type)", async () => {
  const { COMMAND_DOCS } = await import("../src/ui/commands.ts");
  for (const name of COMMAND_NAMES) {
    assert.ok((COMMAND_DOCS[name] ?? "").length > 5, name);
  }
});
