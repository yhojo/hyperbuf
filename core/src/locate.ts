// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

// Maps a place pointed at in the viewer (selection, click) to a position in the original Markdown.
// The foundation that keeps "the position being viewed" and "the position to edit" from silently diverging (docs/dev/edit-location.md §4).
//
// Policy:
//  - Positions are derived reliably from the syntax tree's position info (block start/end offsets), not by searching for text
//  - A fine-grained position inside a block is exact only when the selected string is found in exactly one place
//    in the block's source text. If it is not found, found several times, or there is no selection, use the whole block (block) and do not hide the ambiguity
//  - For verification, attach the string expected at that position (expect) and the surrounding context

export interface Position {
  /** 1-based. */
  line: number;
  /** 1-based. Counted in code points (Emacs characters), not UTF-16 units. */
  column: number;
}

export interface SourceRange {
  start: Position;
  /** End position (the character at that position is not included). */
  end: Position;
}

export type Precision = "exact" | "block";

export interface SourceLocation {
  /** Path of the rendered document (relative if inside a project, absolute if inside a trusted root). */
  path: string;
  range: SourceRange;
  precision: Precision;
  /** The original Markdown string that should be in that range (newlines normalized to LF). If long, only the beginning. */
  expect: string;
  expectTruncated: boolean;
  context: { before: string; after: string };
  /** The string selected in the viewer (as displayed). Empty if there is no selection. */
  selection: string;
  /** The rendered version (the buffer's version). */
  version: number;
}

export interface LocateInput {
  path: string;
  /** The full original Markdown text of the rendered version. */
  text: string;
  version: number;
  /** The original position (UTF-16 offsets) of the pointed block (the whole span if the selection crosses several blocks). */
  blockStart: number;
  blockEnd: number;
  /** The selection in the viewer. An empty string if none. */
  selection: string;
}

export const EXPECT_LIMIT = 500;
export const CONTEXT_LENGTH = 40;

/** Start offset of each line, split by newlines (CRLF, CR, LF). */
export function lineStarts(text: string): number[] {
  const starts = [0];
  for (let i = 0; i < text.length; i++) {
    const c = text.charCodeAt(i);
    if (c === 13 /* CR */) {
      if (text.charCodeAt(i + 1) === 10) i += 1;
      starts.push(i + 1);
    } else if (c === 10 /* LF */) {
      starts.push(i + 1);
    }
  }
  return starts;
}

const codePoints = (s: string): number => {
  let n = 0;
  for (const _ of s) n += 1;
  return n;
};

/** Converts a UTF-16 offset to (line, column). The column is the number of code points from the line start + 1. */
export function offsetToPosition(
  starts: readonly number[],
  text: string,
  offset: number,
): Position {
  let lo = 0;
  let hi = starts.length - 1;
  while (lo < hi) {
    const mid = (lo + hi + 1) >> 1;
    if ((starts[mid] ?? 0) <= offset) lo = mid;
    else hi = mid - 1;
  }
  const lineStart = starts[lo] ?? 0;
  return { line: lo + 1, column: codePoints(text.slice(lineStart, offset)) + 1 };
}

const normalizeNewlines = (s: string): string => s.replace(/\r\n?/g, "\n");

/** Surrounding context. Does not cut a surrogate pair in the middle. */
function sliceSafe(text: string, from: number, to: number): string {
  return normalizeNewlines(
    text
      .slice(from, to)
      .replace(/^[\udc00-\udfff]/, "")
      .replace(/[\ud800-\udbff]$/, ""),
  );
}

function truncate(s: string, limit: number): { text: string; truncated: boolean } {
  const chars = Array.from(s);
  return chars.length > limit
    ? { text: chars.slice(0, limit).join(""), truncated: true }
    : { text: s, truncated: false };
}

/** The offset if the selected string appears in exactly one place in the block's source text. Otherwise null. */
export function uniqueMatch(blockText: string, selection: string): number | null {
  if (!selection) return null;
  const first = blockText.indexOf(selection);
  if (first < 0) return null;
  return blockText.indexOf(selection, first + 1) < 0 ? first : null;
}

export function locateInSource(input: LocateInput): SourceLocation {
  const { text, blockStart, blockEnd } = input;
  const selection = input.selection.trim();
  const blockText = text.slice(blockStart, blockEnd);

  let start = blockStart;
  let end = blockEnd;
  let precision: Precision = "block";
  const match = uniqueMatch(blockText, selection);
  if (match !== null) {
    start = blockStart + match;
    end = start + selection.length;
    precision = "exact";
  }

  const starts = lineStarts(text);
  const { text: expect, truncated } = truncate(
    normalizeNewlines(text.slice(start, end)),
    EXPECT_LIMIT,
  );
  return {
    path: input.path,
    range: {
      start: offsetToPosition(starts, text, start),
      end: offsetToPosition(starts, text, end),
    },
    precision,
    expect,
    expectTruncated: truncated,
    context: {
      before: sliceSafe(text, Math.max(0, start - CONTEXT_LENGTH), start),
      after: sliceSafe(text, end, end + CONTEXT_LENGTH),
    },
    selection: input.selection,
    version: input.version,
  };
}
