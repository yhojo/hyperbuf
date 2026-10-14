// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

// 利用者のキー割り当て(設定ファイルの `keybindings`)を、標準の割り当てに重ねる。DOM に依存しない純粋な関数。
//
//   "keybindings": { "C-x 2": "split-below", "C-f": null, "M-p": "back" }
//     コマンド名 → その割り当てを足す(同じキーの標準の割り当ては、置き換わる)
//     null      → そのキーの標準の割り当てを外す
//
// 不正なもの(不明なコマンド、不正なキー表記、他の割り当てとの衝突)は、無視して、理由を `problems` に残す
// (describe-bindings で見られる)。処理の順序は、設定の並びに依存しない: 解除(null)が先、割り当ては、キーの順。

import { createKeymap } from "./keys.ts";

export type Overrides = Record<string, string | null>;

export interface BindingsResult {
  bindings: Record<string, string>;
  problems: string[];
}

/** キー 1 つの表記: 修飾キーは、C- M- s- S- の順。本体は、1 文字か、名前つきのキー。 */
const KEY = /^(?:C-)?(?:M-)?(?:s-)?(?:S-)?(?:RET|ESC|TAB|SPC|DEL|up|down|left|right|[^\s])$/u;
export const MAX_SEQUENCE_KEYS = 4;
/** 取り消しに使う(キー入力の処理が、直接扱う)ので、割り当てを変えられないキー。 */
const RESERVED = new Set(["C-g"]);

export function isValidKeySequence(sequence: string): boolean {
  const keys = sequence.split(" ");
  return keys.length >= 1 && keys.length <= MAX_SEQUENCE_KEYS && keys.every((k) => KEY.test(k));
}

export function applyOverrides(
  defaults: Readonly<Record<string, string>>,
  overrides: Overrides,
  known: ReadonlySet<string>,
): BindingsResult {
  let bindings: Record<string, string> = { ...defaults };
  const problems: string[] = [];
  // 解除(null)を先に、割り当てを後に。それぞれ、キーの順(設定の並びに依存しない)
  const entries = Object.entries(overrides).sort(
    ([a, av], [b, bv]) => Number(bv === null) - Number(av === null) || a.localeCompare(b),
  );
  for (const [sequence, value] of entries) {
    if (!isValidKeySequence(sequence)) {
      problems.push(
        `"${sequence}": invalid key notation (e.g. C-x 2, M-x, s-[; modifiers in the order C- M- s- S-, at most ${MAX_SEQUENCE_KEYS} keys)`,
      );
      continue;
    }
    if (RESERVED.has(sequence)) {
      problems.push(`"${sequence}" is reserved for quitting and cannot be rebound`);
      continue;
    }
    if (value === null) {
      if (sequence in bindings) delete bindings[sequence];
      else problems.push(`"${sequence}": not bound, so it cannot be removed`);
      continue;
    }
    if (typeof value !== "string" || !known.has(value)) {
      problems.push(`"${sequence}": unknown command: ${String(value)}`);
      continue;
    }
    const candidate = { ...bindings, [sequence]: value };
    try {
      createKeymap(candidate);
    } catch {
      problems.push(
        `"${sequence}": conflicts with another binding (a key cannot be both a prefix and a command)`,
      );
      continue;
    }
    bindings = candidate;
  }
  return { bindings, problems };
}

/** コマンドごとの、割り当てられているキー(キー列の昇順)。 */
export function keysByCommand(bindings: Readonly<Record<string, string>>): Map<string, string[]> {
  const map = new Map<string, string[]>();
  for (const [sequence, command] of Object.entries(bindings)) {
    map.set(command, [...(map.get(command) ?? []), sequence]);
  }
  for (const keys of map.values()) keys.sort();
  return map;
}
