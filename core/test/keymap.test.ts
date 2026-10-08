import assert from "node:assert/strict";
import test from "node:test";
import { COMMAND_NAMES } from "../src/ui/commands.ts";
import { DEFAULT_BINDINGS, defaultKeymap } from "../src/ui/keymap.ts";

test("標準のキー割り当ては、競合なく構築できる", () => {
  assert.doesNotThrow(() => defaultKeymap());
});

test("キー割り当てが指すコマンドは、すべて定義されている", () => {
  const names = new Set<string>(COMMAND_NAMES);
  for (const [keys, command] of Object.entries(DEFAULT_BINDINGS)) {
    assert.ok(names.has(command), `${keys} → ${command} は未定義のコマンド`);
  }
});

test("Back / Forward は C-b / C-f と Cmd+[ / Cmd+] に割り当てる(合意済み)", () => {
  assert.equal(DEFAULT_BINDINGS["C-b"], "back");
  assert.equal(DEFAULT_BINDINGS["C-f"], "forward");
  assert.equal(DEFAULT_BINDINGS["s-["], "back");
  assert.equal(DEFAULT_BINDINGS["s-]"], "forward");
});

test("M-x の候補になるコマンド名に重複がない", () => {
  assert.equal(new Set(COMMAND_NAMES).size, COMMAND_NAMES.length);
});
