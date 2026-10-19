// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

// Overlays the user's key bindings (`keybindings` in the config file) on the default bindings. A pure function with no DOM dependency.
//
//   "keybindings": { "C-x 2": "split-below", "C-f": null, "M-p": "back" }
//     command name -> add that binding (replaces the default binding for the same key)
//     null         -> remove the default binding for that key
//
// Invalid entries (unknown command, invalid key notation, conflict with another binding) are ignored and the reason is kept in `problems`
// (visible in describe-bindings). Processing order does not depend on the config order: removals (null) first, then bindings, in key order.

import { createKeymap } from "./keys.ts";

export type Overrides = Record<string, string | null>;

export interface BindingsResult {
  bindings: Record<string, string>;
  problems: string[];
}

/** Notation of one key: modifiers in the order C- M- s- S-. The base is one character or a named key. */
const KEY = /^(?:C-)?(?:M-)?(?:s-)?(?:S-)?(?:RET|ESC|TAB|SPC|DEL|up|down|left|right|[^\s])$/u;
export const MAX_SEQUENCE_KEYS = 4;
/** Keys whose binding cannot be changed, because they are used for cancel (handled directly by key input processing). */
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
  // Removals (null) first, then bindings, each in key order (independent of the config order)
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

/** Keys bound to each command (key sequences in ascending order). */
export function keysByCommand(bindings: Readonly<Record<string, string>>): Map<string, string[]> {
  const map = new Map<string, string[]>();
  for (const [sequence, command] of Object.entries(bindings)) {
    map.set(command, [...(map.get(command) ?? []), sequence]);
  }
  for (const keys of map.values()) keys.sort();
  return map;
}
