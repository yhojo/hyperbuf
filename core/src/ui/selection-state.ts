// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

// Saving and restoring the selection (session). A selection is represented by positions in the displayed text of a window's body (the same index as isearch).

import { MAX_SELECTION } from "../session.ts";
import type { SessionSelection } from "../session.ts";
import { currentEntry, windows } from "../model.ts";
import type { AppContext } from "./context.ts";
import { buildIndex, rangeFor } from "./isearch-dom.ts";
import type { TextIndex } from "./isearch-dom.ts";

/** Turns a range end (`node`, `offset`) into an index position. null if it is somewhere not in the index (such as a copy of math). */
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
  // When the end is an element (e.g. a paragraph selection), use the nearest text before or after that point
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

/** The current selection (the one inside the window's body). null if none. */
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

/** Restores the saved selection. Does nothing if the text at that position does not match (the document has changed). */
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
