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

test("標準の割り当てに、利用者の設定を重ねられる(describe-bindings の割り当ても含めて)", async () => {
  const { resolveBindings } = await import("../src/ui/keymap.ts");
  const r = resolveBindings({ "M-p": "back", "C-f": null, "C-x 9": "no-such" });
  assert.equal(r.bindings["M-p"], "back");
  assert.ok(!("C-f" in r.bindings));
  assert.equal(r.problems.length, 1);
  assert.equal(resolveBindings(undefined).problems.length, 0);
});

test("C-h b は、describe-bindings", () => {
  assert.equal(DEFAULT_BINDINGS["C-h b"], "describe-bindings");
});

test("すべてのコマンドに、説明がある(型で漏れを検出する COMMAND_DOCS)", async () => {
  const { COMMAND_DOCS } = await import("../src/ui/commands.ts");
  for (const name of COMMAND_NAMES) {
    assert.ok((COMMAND_DOCS[name] ?? "").length > 5, name);
  }
});
