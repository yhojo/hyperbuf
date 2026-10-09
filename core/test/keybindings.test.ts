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

test("キー表記の検証", () => {
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
    // C-M-s は、修飾キーの順(C- M- s- S-)に合っているので、正しい
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

test("割り当てを足す・置き換える・外す", () => {
  const r = applyOverrides(defaults, { "M-p": "back", "C-f": null, "C-x 2": "next-link" }, known);
  assert.deepEqual(r.problems, []);
  assert.equal(r.bindings["M-p"], "back");
  assert.ok(!("C-f" in r.bindings)); // 外した
  assert.equal(r.bindings["C-x 2"], "next-link"); // 置き換えた
  assert.equal(r.bindings["C-b"], "back"); // 他は、そのまま
  assert.doesNotThrow(() => createKeymap(r.bindings));
});

test("標準の割り当てを変えない(元のオブジェクトは、不変)", () => {
  const before = JSON.stringify(defaults);
  applyOverrides(defaults, { "C-f": null, "M-p": "back" }, known);
  assert.equal(JSON.stringify(defaults), before);
});

test("不明なコマンド・不正な表記・割り当てのないキーの解除は、無視して理由を残す", () => {
  const r = applyOverrides(
    defaults,
    { "M-q": "no-such-command", "Ctrl-x": "back", "M-z": null, "M-w": "back" },
    known,
  );
  assert.equal(r.problems.length, 3);
  assert.ok(r.problems.some((p) => p.includes("不明なコマンド")));
  assert.ok(r.problems.some((p) => p.includes("表記が不正")));
  assert.ok(r.problems.some((p) => p.includes("外せません")));
  assert.equal(r.bindings["M-w"], "back"); // 正しいものは、適用される
  assert.ok(!("M-q" in r.bindings));
});

test("C-g は、取り消しに予約されている", () => {
  const r = applyOverrides(defaults, { "C-g": "back" }, known);
  assert.ok(r.problems[0]?.includes("予約"));
  assert.ok(!("C-g" in r.bindings));
});

test("プレフィックスとコマンドの衝突は、無視する(外してから割り当てれば、できる)", () => {
  // C-x は、C-x 2 などのプレフィックス
  const conflict = applyOverrides(defaults, { "C-x": "back" }, known);
  assert.ok(conflict.problems[0]?.includes("衝突"));
  assert.ok(!("C-x" in conflict.bindings));
  // C-x 2 の下に、さらに割り当てると、C-x 2 がコマンドとプレフィックスの両方になる
  const deeper = applyOverrides(defaults, { "C-x 2 a": "back" }, known);
  assert.ok(deeper.problems[0]?.includes("衝突"));
  // 先に、外す(解除は、並びに関係なく先に処理される)
  const ok = applyOverrides(defaults, { "C-x 2 a": "back", "C-x 2": null }, known);
  assert.deepEqual(ok.problems, []);
  assert.equal(ok.bindings["C-x 2 a"], "back");
});

test("設定の並びに依存しない(解除が先)", () => {
  const a = applyOverrides(defaults, { "C-f": null, "C-f ": "back" } as never, known);
  const b = applyOverrides(defaults, { "M-a": "back", "C-b": null }, known);
  const c = applyOverrides(defaults, { "C-b": null, "M-a": "back" }, known);
  assert.deepEqual(b, c);
  assert.ok(a.problems.length >= 0);
});

test("コマンドごとのキー", () => {
  const keys = keysByCommand({ "C-f": "forward", "s-]": "forward", "C-b": "back" });
  assert.deepEqual(keys.get("forward"), ["C-f", "s-]"]);
  assert.deepEqual(keys.get("back"), ["C-b"]);
});

test("describe-bindings の内容: 割り当て済み・キーなし・設定の問題", () => {
  const md = renderBindingsHelp({
    docs: { forward: "進む|戻る", back: "戻る", "next-link": "次のリンク" },
    bindings: { "C-f": "forward", "s-]": "forward", "C-b": "back" },
    problems: ["「M-q」: 不明なコマンドです: x"],
  });
  assert.match(md, /^# キー割り当て/);
  assert.match(md, /## 設定の問題[\s\S]*不明なコマンドです/);
  assert.match(md, /\| `C-f`、 `s-]` \| `forward` \| 進む\\\|戻る \|/); // 表の区切りを壊さない
  assert.match(md, /## キーなし[\s\S]*\| `next-link` \| 次のリンク \|/);
  const none = renderBindingsHelp({
    docs: { back: "x" },
    bindings: { "C-b": "back" },
    problems: [],
  });
  assert.doesNotMatch(none, /設定の問題/);
});
