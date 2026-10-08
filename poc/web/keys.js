// キーイベント → "C-x" 形式の名前、およびプレフィックス付きキーマップの状態機械。

const NAMED = {
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

// macOS の Option は文字を変えてしまうので、修飾キー付きの英数字は code から求める。
export function keyName(e) {
  if (MODIFIER_ONLY.has(e.key)) return null;
  let base;
  const hasMod = e.ctrlKey || e.altKey || e.metaKey;
  const code = /^Key([A-Z])$/.exec(e.code ?? "");
  const digit = /^Digit([0-9])$/.exec(e.code ?? "");
  if (hasMod && code) base = code[1].toLowerCase();
  else if (hasMod && digit) base = digit[1];
  else base = NAMED[e.key] ?? e.key;

  let mods = "";
  if (e.ctrlKey) mods += "C-";
  if (e.altKey) mods += "M-";
  if (e.metaKey) mods += "s-";
  const named = Object.values(NAMED).includes(base) || base.length > 1;
  if (e.shiftKey && (named || hasMod)) mods += "S-";
  return mods + base;
}

// bindings: { "C-x 2": "split-below", "C-f": "forward" }
export function createKeymap(bindings) {
  const root = {};
  for (const [seq, command] of Object.entries(bindings)) {
    const keys = seq.split(" ");
    let node = root;
    keys.slice(0, -1).forEach((k) => {
      if (typeof node[k] === "string") throw new Error(`${seq}: ${k} is already a command`);
      node = node[k] ??= {};
    });
    const last = keys[keys.length - 1];
    if (typeof node[last] === "object") throw new Error(`${seq}: conflicts with a prefix`);
    node[last] = command;
  }
  return root;
}

export function createDispatcher(keymap) {
  let pending = [];
  return {
    get pending() {
      return pending;
    },
    reset() {
      pending = [];
    },
    // -> { type: "command", command } | { type: "prefix", pending } | { type: "unbound", keys }
    feed(name) {
      let node = keymap;
      for (const k of pending) node = node[k];
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
