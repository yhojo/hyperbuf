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

/** macOS の Option は文字を変えてしまうので、修飾キー付きの英数字は code から求める。 */
export function keyName(e: KeyEventLike): string | null {
  if (MODIFIER_ONLY.has(e.key)) return null;
  const hasMod = e.ctrlKey || e.altKey || e.metaKey;
  const code = /^Key([A-Z])$/.exec(e.code ?? "")?.[1];
  const digit = /^Digit([0-9])$/.exec(e.code ?? "")?.[1];
  let base: string;
  if (hasMod && code) base = code.toLowerCase();
  else if (hasMod && digit) base = digit;
  else base = NAMED[e.key] ?? e.key;

  let mods = "";
  if (e.ctrlKey) mods += "C-";
  if (e.altKey) mods += "M-";
  if (e.metaKey) mods += "s-";
  if (e.shiftKey && (base.length > 1 || hasMod)) mods += "S-";
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
