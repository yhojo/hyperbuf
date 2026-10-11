// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

// キーイベント → "C-x" 形式の名前、およびプレフィックス付きキーマップの状態機械。

export interface KeyEventLike {
  key: string;
  code?: string;
  ctrlKey: boolean;
  altKey: boolean;
  metaKey: boolean;
  shiftKey: boolean;
}

const NAMED: Record<string, string> = {
  Enter: "RET",
  Escape: "ESC",
  Tab: "TAB",
  " ": "SPC",
  Backspace: "DEL",
  ArrowUp: "up",
  ArrowDown: "down",
  ArrowLeft: "left",
  ArrowRight: "right",
};

const MODIFIER_ONLY = new Set(["Control", "Alt", "Meta", "Shift", "CapsLock"]);

/**
 * 記号キー(US 配列): 物理キー → [押したときの文字, Shift を押したときの文字]。
 * macOS の Option は、`event.key` を別の文字(`≥` など)にしてしまうので、修飾キーつきの記号は、これで求める。
 * Emacs は `M-S-,` ではなく `M-<` と書く(Shift で変わる記号には、`S-` を付けない)。
 */
const SYMBOLS: Record<string, [string, string]> = {
  Backquote: ["`", "~"],
  Minus: ["-", "_"],
  Equal: ["=", "+"],
  BracketLeft: ["[", "{"],
  BracketRight: ["]", "}"],
  Backslash: ["\\", "|"],
  Semicolon: [";", ":"],
  Quote: ["'", '"'],
  Comma: [",", "<"],
  Period: [".", ">"],
  Slash: ["/", "?"],
  Digit1: ["1", "!"],
  Digit2: ["2", "@"],
  Digit3: ["3", "#"],
  Digit4: ["4", "$"],
  Digit5: ["5", "%"],
  Digit6: ["6", "^"],
  Digit7: ["7", "&"],
  Digit8: ["8", "*"],
  Digit9: ["9", "("],
  Digit0: ["0", ")"],
};

/** macOS の Option は文字を変えてしまうので、修飾キー付きの英数字は code から求める。 */
export function keyName(e: KeyEventLike): string | null {
  if (MODIFIER_ONLY.has(e.key)) return null;
  const hasMod = e.ctrlKey || e.altKey || e.metaKey;
  const code = /^Key([A-Z])$/.exec(e.code ?? "")?.[1];
  const symbol = SYMBOLS[e.code ?? ""];
  let base: string;
  // Shift で記号が変わるキーは、変わったあとの記号(`<` など)にして、`S-` は付けない
  let shiftApplied = false;
  if (hasMod && code) base = code.toLowerCase();
  else if (hasMod && symbol) {
    base = e.shiftKey ? symbol[1] : symbol[0];
    shiftApplied = e.shiftKey;
  } else base = NAMED[e.key] ?? e.key;

  let mods = "";
  if (e.ctrlKey) mods += "C-";
  if (e.altKey) mods += "M-";
  if (e.metaKey) mods += "s-";
  if (e.shiftKey && !shiftApplied && (base.length > 1 || hasMod)) mods += "S-";
  return mods + base;
}

/** キー列 → コマンド名 または 下位のキーマップ。 */
export interface Keymap {
  [key: string]: string | Keymap;
}

/** bindings: { "C-x 2": "split-below", "C-f": "forward" } */
export function createKeymap(bindings: Record<string, string>): Keymap {
  const root: Keymap = {};
  for (const [seq, command] of Object.entries(bindings)) {
    const keys = seq.split(" ");
    const last = keys.pop();
    if (last === undefined) continue;
    let node = root;
    for (const k of keys) {
      const next = node[k];
      if (typeof next === "string") throw new Error(`${seq}: ${k} is already a command`);
      node = node[k] = next ?? {};
    }
    if (typeof node[last] === "object") throw new Error(`${seq}: conflicts with a prefix`);
    node[last] = command;
  }
  return root;
}

export type DispatchResult =
  | { type: "command"; command: string }
  | { type: "prefix"; pending: string[] }
  | { type: "unbound"; keys: string[] };

export interface Dispatcher {
  readonly pending: readonly string[];
  reset(): void;
  feed(name: string): DispatchResult;
}

export function createDispatcher(keymap: Keymap): Dispatcher {
  let pending: string[] = [];
  return {
    get pending() {
      return pending;
    },
    reset() {
      pending = [];
    },
    feed(name) {
      let node: Keymap = keymap;
      for (const k of pending) {
        const next = node[k];
        if (typeof next !== "object") break;
        node = next;
      }
      const next = node[name];
      if (next === undefined) {
        const keys = [...pending, name];
        pending = [];
        return { type: "unbound", keys };
      }
      if (typeof next === "string") {
        pending = [];
        return { type: "command", command: next };
      }
      pending = [...pending, name];
      return { type: "prefix", pending };
    },
  };
}
