// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

// Incremental search within a document (C-s / C-r). Searches the text of the displayed document (DOM).
// Search decisions live in ../isearch.ts (pure functions). This file handles the text index, ranges, highlighting and scrolling.
//
//  - On every input, recount matches and select the first match at or after the reference position
//  - C-s goes next, C-r previous (at an end, wraps to the opposite end: "Wrapped"). C-s with an empty query uses the previous query
//  - RET: stay at that position (the match stays selected). C-g / ESC: return to where the search started
//  - A query containing uppercase is case-sensitive (otherwise case-insensitive)

import { findAll, firstMatch, isCaseSensitive, step } from "../isearch.ts";
import type { AppContext } from "./context.ts";

export interface TextIndex {
  text: string;
  nodes: { node: Text; start: number }[];
}

/** Places excluded from search (the MathML copy of math, diagrams, scripts). */
const SKIP = ".katex-mathml, svg, script, style";
/** Separator, so that matches never span blocks. */
const BLOCKS = "p,li,h1,h2,h3,h4,h5,h6,pre,td,th,blockquote,summary,dt,dd,div";
/** Upper limit of highlighted matches (too many makes it slow). */
const HIGHLIGHT_LIMIT = 2000;

export function buildIndex(root: HTMLElement): TextIndex {
  const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT, {
    acceptNode: (n) =>
      n.parentElement?.closest(SKIP) ? NodeFilter.FILTER_REJECT : NodeFilter.FILTER_ACCEPT,
  });
  let text = "";
  const nodes: TextIndex["nodes"] = [];
  let lastBlock: Element | null | undefined;
  for (let n = walker.nextNode(); n; n = walker.nextNode()) {
    const node = n as Text;
    if (!node.data) continue;
    const block = node.parentElement?.closest(BLOCKS) ?? null;
    if (lastBlock !== undefined && block !== lastBlock) text += "\n";
    lastBlock = block;
    nodes.push({ node, start: text.length });
    text += node.data;
  }
  return { text, nodes };
}

/** The text node containing `offset` (or whose end equals `offset`). */
function nodeAt(index: TextIndex, offset: number): { node: Text; start: number } | null {
  let lo = 0;
  let hi = index.nodes.length - 1;
  while (lo < hi) {
    const mid = (lo + hi + 1) >> 1;
    if ((index.nodes[mid]?.start ?? Infinity) <= offset) lo = mid;
    else hi = mid - 1;
  }
  return index.nodes[lo] ?? null;
}

export function rangeFor(index: TextIndex, start: number, end: number): Range | null {
  const a = nodeAt(index, start);
  const b = nodeAt(index, end - 1);
  if (!a || !b) return null;
  const range = document.createRange();
  range.setStart(a.node, start - a.start);
  range.setEnd(b.node, end - b.start);
  return range;
}

/** Position of the first text visible at the top of the screen (the reference for starting a search). */
function firstVisibleOffset(index: TextIndex, content: HTMLElement): number {
  const top = content.getBoundingClientRect().top;
  for (const { node, start } of index.nodes) {
    const rect = node.parentElement?.getBoundingClientRect();
    if (rect && rect.bottom > top + 1) return start;
  }
  return 0;
}

function highlights(): HighlightRegistry | null {
  return typeof CSS !== "undefined" && "highlights" in CSS && typeof Highlight !== "undefined"
    ? CSS.highlights
    : null;
}

function clearHighlights(): void {
  highlights()?.delete("hb-search");
  highlights()?.delete("hb-search-current");
}

function revealRange(content: HTMLElement, range: Range): void {
  const rect = range.getBoundingClientRect();
  const box = content.getBoundingClientRect();
  const margin = content.clientHeight * 0.15;
  if (rect.top < box.top + margin || rect.bottom > box.bottom - margin) {
    content.scrollTop += rect.top - box.top - content.clientHeight / 3;
  }
}

let lastQuery = "";

/** Starts incremental search within a document. Does not end until confirmed or cancelled. */
export async function startIsearch(ctx: AppContext, direction: 1 | -1): Promise<void> {
  const { minibuffer, views, echo } = ctx;
  const content = views.selected().content;
  const index = buildIndex(content);
  const origin = { scrollTop: content.scrollTop, from: firstVisibleOffset(index, content) };
  let dir: 1 | -1 = direction;
  let matches: number[] = [];
  let current: number | null = null;
  let query = "";
  // Reference position to search again from when the input changes: the last selected match (or the position where the search started).
  // Not lost even if the query becomes temporarily empty (confirming Japanese input clears it once and re-enters it)
  let anchor = origin.from;

  const labelOf = (): string => (dir === 1 ? "I-search: " : "I-search backward: ");

  const select = (): void => {
    clearHighlights();
    const selection = window.getSelection();
    // When highlighting is available, do not touch the selection (manipulating the selection while the input field has focus
    // makes WKWebView drop the input field's focus)
    if (!highlights()) selection?.removeAllRanges();
    if (current === null) return;
    const start = matches[current];
    const range = start === undefined ? null : rangeFor(index, start, start + query.length);
    if (!range) return;
    const registry = highlights();
    // Creating a selection in the document makes WKWebView take focus from the minibuffer's input field, and later key input
    // no longer arrives. While typing, show matches only by highlighting and make the selection after confirming (use the selection
    // as a substitute only when highlighting is unavailable)
    if (!registry) selection?.addRange(range);
    revealRange(content, range);
    if (registry) {
      const all = matches
        .slice(0, HIGHLIGHT_LIMIT)
        .map((m) => rangeFor(index, m, m + query.length))
        .filter((r): r is Range => r !== null);
      registry.set("hb-search", new Highlight(...all));
      registry.set("hb-search-current", new Highlight(range));
    }
  };

  const show = (wrapped: boolean): void => {
    const counter =
      current === null
        ? query
          ? "Failing"
          : ""
        : `[${current + 1}/${matches.length}]${wrapped ? " Wrapped" : ""}`;
    session.setCount(counter);
    session.setLabel(`${current === null && query ? "Failing " : ""}${labelOf()}`);
    select();
  };

  const remember = (): void => {
    if (current !== null) anchor = matches[current] ?? anchor;
  };

  // composing: during Japanese input conversion, do not move the reference position (do not get dragged by intermediate matches such as "さ", "さん"...,
  // and search for the confirmed word from where the conversion started)
  const search = (text: string, from: number, composing = false): void => {
    query = text;
    matches = findAll(index.text, query, isCaseSensitive(query));
    const first = firstMatch(matches, from, dir);
    current = first.index;
    if (!composing) remember();
    show(first.wrapped);
  };

  const session = minibuffer.live(labelOf(), {
    onInput(text, composing) {
      // For input that does not change the query (e.g. confirming Japanese input), do not search again (the selected match would move)
      if (text === query && current !== null) return;
      // When the input changes, search again from the reference position
      search(text, anchor, composing);
    },
    onKey(name) {
      if (name !== "C-s" && name !== "C-r") return false;
      dir = name === "C-s" ? 1 : -1;
      if (!query && lastQuery) {
        // When the query is empty, use the previous query
        session.setText(lastQuery);
        search(lastQuery, anchor);
        return true;
      }
      const next = step(matches.length, current, dir);
      current = next.index;
      remember();
      show(next.wrapped);
      return true;
    },
  });

  const accepted = await session.done;
  clearHighlights();
  // As in Emacs, remember the query even when leaving by cancelling (C-g) (usable with the next C-s C-s)
  if (query) lastQuery = query;
  if (accepted && query) {
    // Leave the match selected (it also becomes the target of "edit in editor" as is). Some WebViews clear the document's selection when the minibuffer's input field
    // loses focus, so select again after closing
    const start = current === null ? undefined : matches[current];
    const range = start === undefined ? null : rangeFor(index, start, start + query.length);
    if (range) {
      const selection = window.getSelection();
      selection?.removeAllRanges();
      selection?.addRange(range);
    }
  } else {
    window.getSelection()?.removeAllRanges();
    content.scrollTop = origin.scrollTop;
  }
  if (accepted && current === null && query) echo.message(`Not found: ${query}`);
}
