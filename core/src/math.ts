// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

// Math compatibility handling (pure functions with no DOM or shell dependency).
//
// Marked 2 and others first unescape backslashes as Markdown, then pass the result to the math engine.
// So the habit of writing `_` inside math as `\_` to avoid Markdown emphasis (`_`) (`$f\_{2}$`) works as is.
// TeX's `\_` is "a literal underscore", so passing it unchanged to KaTeX does not make a subscript and shows `f_2`.
// GitHub and others pass the math content through as is (`\_` stays an underscore), so this is Marked 2-style compatibility handling.

/** Commands whose argument treats `\_` as "a literal underscore" (text and font commands). */
const LITERAL_ARGUMENT_COMMANDS = new Set([
  "text",
  "textrm",
  "textbf",
  "textit",
  "textsf",
  "texttt",
  "mathrm",
  "mathbf",
  "mathit",
  "mathsf",
  "mathtt",
  "operatorname",
  "mbox",
  "hbox",
]);

/**
 * Turns `\_` in math (TeX) back into `_` (a subscript). The following are left as is.
 *  - `\\_` (a `_` after a line break). `\\` is one symbol, and the `_` right after it is left as is
 *  - Inside arguments of `\text{…}`, `\mathrm{…}`, `\operatorname{…}`, etc. (`\text{snake\_case}`, `\mathrm{max\_value}`)
 */
export function unescapeMathUnderscores(tex: string): string {
  if (!tex.includes("\\_")) return tex;
  let out = "";
  let i = 0;
  let depth = 0;
  /** Just after a command that takes an argument and treats it as text; waiting for `{`. */
  let pending = false;
  /** Brace depth inside a text-style argument (counted from the outside of the nesting). */
  const literal: number[] = [];
  while (i < tex.length) {
    const c = tex[i] as string;
    if (c === "\\") {
      const next = tex[i + 1];
      if (next !== undefined && /[A-Za-z]/.test(next)) {
        const name = /^[A-Za-z]+/.exec(tex.slice(i + 1))?.[0] ?? "";
        pending = LITERAL_ARGUMENT_COMMANDS.has(name);
        out += `\\${name}`;
        i += 1 + name.length;
        continue;
      }
      if (next === "_" && literal.length === 0) out += "_";
      else out += next === undefined ? "\\" : `\\${next}`;
      pending = false;
      i += 2;
      continue;
    }
    if (c === "{") {
      depth += 1;
      if (pending) literal.push(depth);
      pending = false;
    } else if (c === "}") {
      if (literal[literal.length - 1] === depth) literal.pop();
      depth = Math.max(0, depth - 1);
    } else if (!/\s/.test(c)) {
      pending = false;
    }
    out += c;
    i += 1;
  }
  return out;
}
