// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

// 選択範囲の保存と復元(セッション)。選択は、window の本文の、表示されたテキスト(isearch と同じ索引)の位置で表す。

import { MAX_SELECTION } from "../session.ts";
import type { SessionSelection } from "../session.ts";
import { currentEntry, windows } from "../model.ts";
import type { AppContext } from "./context.ts";
import { buildIndex, rangeFor } from "./isearch-dom.ts";
import type { TextIndex } from "./isearch-dom.ts";

/** 範囲の端(`node`, `offset`)を、索引の位置にする。索引にない場所(数式の複製など)なら null。 */
function offsetOf(
  index: TextIndex,
  node: Node,
  offset: number,
  edge: "start" | "end",
): number | null {
  if (node.nodeType === Node.TEXT_NODE) {
    const hit = index.nodes.find((n) => n.node === node);
    return hit ? hit.start + offset : null;
  }
  // 要素が端のとき(段落の選択など)は、その点の前後で、最も近いテキストを使う
  const point = document.createRange();
  point.setStart(node, offset);
  point.collapse(true);
  if (edge === "start") {
    const next = index.nodes.find((n) => point.comparePoint(n.node, 0) >= 0);
    return next ? next.start : index.text.length;
  }
  let end = 0;
  for (const n of index.nodes) {
    if (point.comparePoint(n.node, n.node.length) <= 0) end = n.start + n.node.length;
  }
  return end;
}

/** いまの選択範囲(window の本文の中にあるもの)。なければ null。 */
export function captureSelection(ctx: AppContext): SessionSelection | null {
  const selection = window.getSelection();
  if (!selection || selection.rangeCount === 0 || selection.isCollapsed) return null;
  const range = selection.getRangeAt(0);
  for (const win of windows(ctx.model)) {
    const content = ctx.views.contentOf(win.id);
    const entry = currentEntry(win);
    if (!content || !entry || !content.contains(range.commonAncestorContainer)) continue;
    const index = buildIndex(content);
    const start = offsetOf(index, range.startContainer, range.startOffset, "start");
    const end = offsetOf(index, range.endContainer, range.endOffset, "end");
    if (start === null || end === null || end <= start || end - start > MAX_SELECTION) return null;
    return { win: win.id, path: entry.path, start, end, text: index.text.slice(start, end) };
  }
  return null;
}

/** 保存した選択範囲を戻す。その位置の文字列が一致しなければ(文書が変わっていれば)、何もしない。 */
export function applySelection(ctx: AppContext, saved: SessionSelection): boolean {
  const content = ctx.views.contentOf(saved.win);
  if (!content) return false;
  const index = buildIndex(content);
  if (index.text.slice(saved.start, saved.end) !== saved.text) return false;
  const range = rangeFor(index, saved.start, saved.end);
  if (!range) return false;
  const selection = window.getSelection();
  selection?.removeAllRanges();
  selection?.addRange(range);
  return true;
}
