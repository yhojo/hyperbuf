// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

// Counts of lines, words and characters of the displayed text (`count-words`). A pure function with no DOM dependency.
//
// What is counted is the displayed (rendered) text, not the original Markdown. This is a viewer, so appearance comes first.
// Measure the original Markdown with Emacs's `count-words`.

export interface Counts {
  /** Number of non-empty lines (a paragraph, list item, table row or code line counts as one line each). */
  lines: number;
  /** Number of words. Languages that do not separate words with spaces, such as Japanese, are counted by dictionary-based word segmentation. */
  words: number;
  /** Number of characters (code points). A line-separating newline counts as one; empty lines are not included. */
  characters: number;
  /** Number of characters excluding whitespace (including newlines). */
  nonWhitespace: number;
}

const segmenter = new Intl.Segmenter(undefined, { granularity: "word" });

export function countText(text: string): Counts {
  // Rendering newlines (blank lines between blocks, etc.) are not counted. Only non-empty lines joined by a single newline form the text whose characters are counted
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

/** Emacs-style message. Example: `Region has 3 lines, 42 words, 210 characters (180 without whitespace)`. */
export function formatCounts(scope: "Region" | "Buffer", c: Counts): string {
  return (
    `${scope} has ${plural(c.lines, "line")}, ${plural(c.words, "word")}, ` +
    `${plural(c.characters, "character")} (${c.nonWhitespace} without whitespace)`
  );
}
