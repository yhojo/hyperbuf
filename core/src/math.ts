// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

// 数式の互換処理(DOM やシェルに依存しない純粋な関数)。
//
// Marked 2 などは、先に Markdown としてバックスラッシュのエスケープを外してから、数式のエンジンに渡す。
// そのため、Markdown の強調(`_`)を避けるために、数式の中の `_` を `\_` と書く習慣(`$f\_{2}$`)が、そのまま通る。
// TeX の `\_` は「文字としての下線」なので、そのまま KaTeX に渡すと、下付き文字にならず、`f_2` と表示される。
// GitHub などは、数式の中身をそのまま渡す(`\_` は下線のまま)ので、これは、Marked 2 流の互換処理。

/** 引数の中では、`\_` が「文字としての下線」を意味するコマンド(テキスト・書体の指定)。 */
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
 * 数式(TeX)の中の `\_` を `_` に戻す(下付き文字にする)。次のものは、そのままにする。
 *  - `\\_`(改行のあとの `_`)。`\\` は 1 つの記号で、直後の `_` は、そのまま
 *  - `\text{…}` `\mathrm{…}` `\operatorname{…}` などの引数の中(`\text{snake\_case}`、`\mathrm{max\_value}`)
 */
export function unescapeMathUnderscores(tex: string): string {
  if (!tex.includes("\\_")) return tex;
  let out = "";
  let i = 0;
  let depth = 0;
  /** 直前が、引数を取る、文字扱いのコマンドで、`{` を待っている。 */
  let pending = false;
  /** 文字扱いの引数の中に入った、波括弧の深さ(入れ子の外側から)。 */
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
