// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

// Derives the pointed block and selection from the on-screen selection / click (the DOM part).
// Mapping to the source position (the pure part) is in ../locate.ts.

import { locateInSource } from "../locate.ts";
import type { SourceLocation } from "../locate.ts";

/** The innermost block that has a source position. */
function blockOf(node: Node | null): HTMLElement | null {
  const element = node instanceof HTMLElement ? node : (node?.parentElement ?? null);
  return element?.closest<HTMLElement>("[data-source-start]") ?? null;
}

function range(el: HTMLElement): { start: number; end: number } | null {
  const start = Number(el.dataset["sourceStart"]);
  const end = Number(el.dataset["sourceEnd"]);
  return Number.isFinite(start) && Number.isFinite(end) ? { start, end } : null;
}

/** The block at the top of the screen (the "place being read" when there is neither a selection nor a click). */
function topBlock(content: HTMLElement): HTMLElement | null {
  let best: HTMLElement | null = null;
  for (const el of content.querySelectorAll<HTMLElement>("[data-source-start]")) {
    if (el.offsetTop <= content.scrollTop + 1) best = el;
    else break;
  }
  return best ?? content.querySelector<HTMLElement>("[data-source-start]");
}

export interface LocateRequest {
  content: HTMLElement;
  path: string;
  text: string;
  version: number;
  /** The right-clicked element (when there is no selection, this is the pointed location). */
  contextTarget: Element | null;
}

/**
 * Turns the location pointed at in the viewer into a position in the source Markdown.
 * Priority: (1) a non-empty selection in the document (2) the right-clicked element (3) the block at the top of the screen.
 */
export function locateFromDom(request: LocateRequest): SourceLocation | null {
  const { content } = request;
  const selection = window.getSelection();
  let startBlock: HTMLElement | null = null;
  let endBlock: HTMLElement | null = null;
  let selected = "";

  if (selection && !selection.isCollapsed && selection.rangeCount > 0) {
    const r = selection.getRangeAt(0);
    if (content.contains(r.startContainer) && content.contains(r.endContainer)) {
      startBlock = blockOf(r.startContainer);
      endBlock = blockOf(r.endContainer);
      selected = selection.toString();
    }
  }
  if (!startBlock && request.contextTarget && content.contains(request.contextTarget)) {
    startBlock = endBlock = blockOf(request.contextTarget);
  }
  if (!startBlock) startBlock = endBlock = topBlock(content);
  if (!startBlock || !endBlock) return null;

  const a = range(startBlock);
  const b = range(endBlock);
  if (!a || !b) return null;
  return locateInSource({
    path: request.path,
    text: request.text,
    version: request.version,
    // A selection spanning multiple blocks is taken as a whole (ambiguous, so it becomes a block)
    blockStart: Math.min(a.start, b.start),
    blockEnd: Math.max(a.end, b.end),
    selection: startBlock === endBlock ? selected : "",
  });
}
