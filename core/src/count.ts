// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

// 表示されているテキストの、行・単語・文字の数(`count-words`)。DOM に依存しない純粋な関数。
//
// 数える対象は、元の Markdown ではなく、表示されているテキスト(描画後)。ビューアなので、見た目を優先する。
// 元の Markdown の数は、Emacs の `count-words` で測る。

export interface Counts {
  /** 空でない行の数(段落・リスト項目・表の行・コードの行が、それぞれ 1 行)。 */
  lines: number;
  /** 単語の数。日本語などの空白で区切らない言語は、辞書による単語分割で数える。 */
  words: number;
  /** 文字の数(コードポイント)。行の区切りの改行は 1 つとして含み、空行は含めない。 */
  characters: number;
  /** 空白(改行を含む)を除いた文字の数。 */
  nonWhitespace: number;
}

const segmenter = new Intl.Segmenter(undefined, { granularity: "word" });

export function countText(text: string): Counts {
  // 描画上の改行(ブロックの間の空行など)は、数えない。空でない行だけを、改行 1 つでつないだものを、文字数の対象にする
  const lines = text
    .split(/\r\n|\r|\n/)
    .map((line) => line.trim())
    .filter((line) => line !== "");
  let words = 0;
  for (const { isWordLike } of segmenter.segment(lines.join("\n"))) if (isWordLike) words += 1;
  const joined = lines.join("\n");
  return {
    lines: lines.length,
    words,
    characters: [...joined].length,
    nonWhitespace: [...joined.replace(/\s/gu, "")].length,
  };
}

const plural = (n: number, noun: string): string => `${n} ${noun}${n === 1 ? "" : "s"}`;

/** Emacs の体裁のメッセージ。例: `Region has 3 lines, 42 words, 210 characters (180 without whitespace)`。 */
export function formatCounts(scope: "Region" | "Buffer", c: Counts): string {
  return (
    `${scope} has ${plural(c.lines, "line")}, ${plural(c.words, "word")}, ` +
    `${plural(c.characters, "character")} (${c.nonWhitespace} without whitespace)`
  );
}
