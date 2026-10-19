// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

// ビューアで指した場所(選択・クリック)を、元の Markdown の位置に対応づける。
// 「表示を見ている位置」と「編集する位置」が、黙って食い違わないための土台(docs/dev/integration-protocol.md §10)。
//
// 方針:
//  - 位置は、構文木の位置情報(ブロックの開始・終了オフセット)から、確実に求める(文言の検索に頼らない)
//  - ブロックの中の細かい位置は、選択した文字列が、ブロックの元の文章の中で「ちょうど 1 か所」に見つかるときだけ、
//    正確(exact)とする。見つからない・複数ある・選択がないときは、ブロック全体(block)にして、曖昧さを隠さない
//  - 照合用に、その位置にあるはずの文字列(expect)と、前後の文脈を添える

export interface Position {
  /** 1 始まり。 */
  line: number;
  /** 1 始まり。コードポイント(Emacs の文字)で数える。UTF-16 の単位ではない。 */
  column: number;
}

export interface SourceRange {
  start: Position;
  /** 終了位置(その位置の文字は含まない)。 */
  end: Position;
}

export type Precision = "exact" | "block";

export interface SourceLocation {
  /** 描画した文書のパス(プロジェクト内なら相対、信頼するルートの内側なら絶対)。 */
  path: string;
  range: SourceRange;
  precision: Precision;
  /** その範囲にあるはずの、元の Markdown の文字列(改行は LF にそろえる)。長いときは、先頭だけ。 */
  expect: string;
  expectTruncated: boolean;
  context: { before: string; after: string };
  /** ビューアで選択していた文字列(表示されているままの文字列)。選択がなければ空。 */
  selection: string;
  /** 描画した版(buffer の version)。 */
  version: number;
}

export interface LocateInput {
  path: string;
  /** 描画した版の、元の Markdown の全文。 */
  text: string;
  version: number;
  /** 指したブロック(選択が複数のブロックにまたがるときは、その全体)の、元の位置(UTF-16 のオフセット)。 */
  blockStart: number;
  blockEnd: number;
  /** ビューアでの選択。なければ空文字列。 */
  selection: string;
}

export const EXPECT_LIMIT = 500;
export const CONTEXT_LENGTH = 40;

/** 改行(CRLF・CR・LF)ごとの、各行の開始オフセット。 */
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

/** UTF-16 のオフセットを、(行, 桁)にする。桁は、行頭からのコードポイント数 + 1。 */
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

/** 前後の文脈。サロゲートペアを、途中で切らない。 */
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

/** 選択した文字列が、ブロックの元の文章の中に、ちょうど 1 か所あれば、そのオフセット。それ以外は null。 */
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
